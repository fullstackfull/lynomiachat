---
agent: 024
scope: Instagram Messaging at runtime — receivable and sendable message types, webhook payloads, messaging window and human agent, rate limits, media/CDN URL behaviour, Instagram-specific error codes, documented restrictions, and message unsend
confidence: medium
sources_normative: 13
sources_observational: 2
---

# Agent 024 — Instagram Messaging runtime

Instagram messaging and Messenger messaging share a Send API surface, a `messages` webhook name and a
24-hour window, and Meta documents them largely in the same tree. They are not the same product at runtime.
This report separates what Meta states for Instagram from what it states for Messenger, because a
troubleshooting article that assumes the Messenger rules will be wrong in at least nine places: the echo
field, read receipts, handover, one-time notifications, sponsored messages, the rate-limit scope, the
high-volume cut-off, inbox folder behaviour, and whether inbound media may be cached.

## 1. Source register

| Row | Source URL | Page title | Product | API / version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api/` | Send Messages | Instagram Platform (Instagram API with Instagram Login) | samples on `graph.instagram.com` **v25.0**; permissions `instagram_business_basic`, `instagram_business_manage_messages` | 2026-10-13 | normative |
| S2 | `https://developers.facebook.com/docs/messenger-platform/reference/webhook-events/messages/` | messages Webhook Event Reference | Messenger Platform | only version named is **v6.0** (fallback example); sticker/image dual-send noted "until August 30, 2026" | 2026-10-13 | normative, **Messenger-oriented** |
| S3 | `https://developers.facebook.com/docs/instagram-platform/webhooks` | Setup Webhooks Subscriptions | Instagram Platform | `graph.instagram.com/v25.0` | 2026-10-13 | normative |
| S4 | `https://developers.facebook.com/docs/messenger-platform/error-codes/` | Common Error Codes | Messenger Platform | version named only for 100–2018328 (product templates need v8+) | 2026-10-13 | normative |
| S5 | `https://developers.facebook.com/documentation/business-messaging/messenger-platform/overview/rate-limiting` | Messenger Platform rate limits | Messenger Platform | none stated | 2026-10-13 | normative |
| S6 | `https://developers.facebook.com/docs/messenger-platform/instagram/features/webhook/` | Webhooks for Instagram Messaging | Messenger Platform / Instagram Messaging | v8.0 (postbacks), v11.0 (`mid` in postbacks), v12.0 (extended reaction types) | 2026-10-13 | normative |
| S7 | `https://developers.facebook.com/docs/messenger-platform/changelog/` | Changelog — Messenger Platform | Messenger Platform | dated entries | 2026-10-13 | normative changelog |
| S8 | `https://developers.facebook.com/documentation/business-messaging/messenger-platform/policy` | Messenger Platform and IG Messaging API policy | Messenger Platform / IG Messaging API | none stated | 2026-10-13 | normative |
| S9 | `https://developers.facebook.com/docs/instagram-platform/overview/` | Overview | Instagram Platform | none stated | 2026-10-13 | normative |
| S10 | `https://developers.facebook.com/documentation/business-messaging/messenger-platform/webhooks` | Meta Webhooks for Messenger Platform | Messenger Platform | none stated | 2026-10-13 | normative |
| S11 | `https://developers.facebook.com/documentation/business-messaging/instagram-messaging/features/story-mention` | Story Mention | Instagram Messaging | none stated | 2026-10-13 | normative |
| S12 | `https://developers.facebook.com/documentation/business-messaging/instagram-messaging/features/send-message` | Send a Message | Instagram Messaging (Messenger Platform) | examples use the placeholder `<API_VERSION>` | 2026-10-13 | normative |
| S13 | `https://developers.facebook.com/documentation/business-messaging/instagram-messaging` | Instagram Messaging | Instagram Messaging | none stated | 2026-10-13 | normative (navigation only — no rules on the page) |
| O1 | `https://developers.facebook.com/community/threads/889163498159993/` | "Instagram media and thumbnail links get expired! How long will these links stay available for access?" | Developer Community Forum | n/a | 2026-10-13 | **observational, unconfirmed** — forum reply, not documentation |
| O2 | — (inference from S4) | the 2534xxx subcode range as "the Instagram family" | — | — | 2026-10-13 | **observational** — S4 labels only some 2534xxx rows as Instagram; the range pattern is my inference |

Pages that exist but returned navigation chrome only, so nothing was extracted from them:
`.../instagram-messaging/features/human-agent` (S13 nav links to it) and
`https://developers.facebook.com/docs/messenger-platform/send-messages/message-tags/`. Both are recorded
as **not checked**, not as "absent".

## 2. The rules

### 2.1 What can be received

Meta's Instagram webhook reference (S6) is the only page that documents the inbound shapes in Instagram
terms. The envelope is `{"object": "instagram", "entry": [{ "id": <IGID>, "time", "messaging": [ ... ] }]}`,
where `entry.id` / `recipient.id` is the business account's Instagram ID and `sender.id` is the customer's
Instagram-scoped ID (IGSID). Every inbound type below is from S6 unless marked.

| Inbound type | How it arrives (S6) | What the payload actually carries |
|---|---|---|
| Text | `message.mid`, `message.text` | text only |
| Media (image, video, audio, file) | `message.attachments[].type` = `image` (image or sticker), `video`, `audio`, `file`; `payload.url` | a CDN URL, no filename, no MIME type, no size |
| Sticker | arrives as `type` = `image` (S6). S2 adds a dedicated `sticker` type with `payload.sticker_id`, and says `image` is **also** sent for stickers until **August 30, 2026** | on Instagram, indistinguishable from an image in S6's list |
| Story reply | `message.reply_to.story.url` (CDN URL) + `message.reply_to.story.id`, alongside the normal `message.text` | the reply text plus a pointer to the story being replied to |
| Story mention | `attachments[].type` = `story_mention`, `payload.url` | a CDN URL to the story only |
| Post / media share | `attachments[].type` = `share`, `payload.url`. **Migrating to `ig_post`** — see §5 | S1: "only the URL of a shared post or media is included" |
| Reel share | `attachments[].type` = `ig_reel` or `reel`, `payload.url`; S2 adds `payload.title` and `payload.reel_video_id` | URL, and on the Messenger reference also title and video id |
| Reaction | its own field, `message_reactions`; the data sits under a top-level `reaction` key with `reaction.mid` (the message reacted to), `reaction.action` = `react`\|`unreact`, and optional `reaction.reaction` (v12.0+: `angry`, `sad`, `wow`, `love`, `like`, `laugh`, `other`) and `reaction.emoji`. Both optional fields are absent on `unreact`. **No echo webhook is delivered for reactions.** | which message, react or unreact, and which reaction |
| Unsend / deleted message | `message.is_deleted` = `true` | **the `mid` and nothing else.** No text, no attachment, no reason, no actor |
| Echo (the business's own outbound) | `message.is_echo` = `true`, delivered on the **`messages`** field | Instagram has no separate `message_echoes` subscription (S10) |
| Unsupported media | `message.is_unsupported` = `true` | a flag; the content is not delivered |
| Ephemeral (disappearing) media | `attachments[].type` = `ephemeral`, **and no URL** | nothing retrievable |
| Inline reply to a message | `message.reply_to.mid` | the replied-to message id. S7 (2025-10-06) adds `reply_to` to the Conversations API and to Message and Echo webhooks with an `is_self_reply` flag |
| Quick reply tap | `message.quick_reply.payload` | the payload string |
| Shops product referral | `message.referral.product.id` | the Instagram Shops product id |
| Click-to-Instagram ad referral | `message.referral` with `ref`, `ad_id`, `source` = `"ADS"`, `type` = `"OPEN_THREAD"`, `ads_context_data` (`ad_title`, `photo_url`, `video_url`) | S2 notes receiving ads referral data requires subscribing to **both** `messages` and `messaging_referrals` |
| Read receipt | field `messaging_seen`, payload `read.mid` | last-seen message id |
| Postback | field `messaging_postbacks`: `postback.mid` (v11.0+), `postback.title`, `postback.payload`. S10: on Instagram this fires for "an Icebreaker option or Generic Template button" | — |

**Voice note.** Meta does not document a distinct Instagram voice-note type. S6 lists `audio` as an
attachment type with `payload.url`, and S1/S12 list audio as a *sendable* type (`aac`, `m4a`, `wav`,
`mp4`). Whether an Instagram voice note arrives as `audio` or as `ephemeral`/`is_unsupported` is
**not stated** on any page checked. Recorded as an ambiguity in §6, not resolved.

**Story mention delivery conditions (S11).** A mention webhook flows in only when the mentioning account
is **public**; if the mentioning account is private, the webhook flows in only when that account **follows**
the professional account. S6 adds that only *story* mentions fire a webhook — **tags on regular posts do not**.

### 2.2 What can be sent

From S1 and S12, which agree on the limits:

| Sendable | Request shape | Documented limit |
|---|---|---|
| Text or link | `message.text` | S1 and S12's basic-message section say "1000 bytes or less", UTF-8. S12's own Limitations section says "under 1000 characters". **The two statements are in the same page and do not agree** — see §6 |
| Image | `attachment.type` = `image`, `payload.url` **or** `payload.attachment_id` | png, jpeg, max **8MB**; up to **ten** attachment objects per message; `url` and `attachment_id` may be mixed in one payload |
| Video | media attachment | mp4, ogg, avi, mov, webm, max **25MB** |
| Audio | media attachment | aac, m4a, wav, mp4, max **25MB** |
| File | media attachment | **PDF only**, max **25MB** (S7: PDF sending added 2025-12-19) |
| Heart sticker | `attachment.type` = `like_heart`, no payload | the only sticker S1/S12 show a send example for |
| Reaction | `sender_action` = `react` with `payload.message_id` and `payload.reaction` (S12's example uses `love`); removed with `sender_action` = `unreact` | S12 does not list the accepted reaction values; S7 (2025-12-02) adds reacting with an emoji, editing a reaction and removing one |
| Published post | `attachment.type` = `MEDIA_SHARE`, `payload.id` | the business **must own** the media |
| Reply to a specific message | `reply_to.mid` | usable with text, media or template messages |
| Templates | Generic, Button, Product templates; Quick Replies; Ice Breakers; Persistent Menu | S12 mentions generic/product templates and persistent menu only as next steps, with no limits. S13's nav lists Generic/Button/Product Template, Quick Replies, Ice Breakers, Persistent Menu. **S12 does not mention button templates or quick replies at all** |
| Typing / mark seen | `sender_action` | S7: available from **2025-09-23** |

**What cannot be sent, as Meta states it:**

- **Group messaging.** S1: "An Instagram professional account can only converse with one customer per
  conversation."
- **One-time notifications.** S8: "One-time notifications are not available for IG Messaging API."
- **Sponsored messages.** S8: "Sponsored messages are not available for IG Messaging API."
- **News messaging.** S8: "and is not available for Instagram Messaging API."
- **Anything, to anyone who has not messaged first.** S1: only after an Instagram user has sent the
  professional account a message can the app send to that user.
- **Anything, to a non-role-holder while the app has Standard Access.** S12: apps with Standard Access can
  only message people who have a role on the app. S4 gives the matching failures (200–2018028 / 200–2018027).
- Beyond those, **S12 does not explicitly enumerate unsupported send types.** Any further "you cannot send
  X on Instagram" claim in a Lynomia article would be unsourced.

### 2.3 The messaging window, and the human agent equivalent

| Rule | Statement | Source |
|---|---|---|
| Standard window | "Your app has 24 hours to respond to any message sent from an Instagram user to your app user." | S1 |
| Standard window (policy wording) | "Businesses have up to 24 hours to respond to a user." | S8 |
| Promotional content inside the window | "Messages sent within the 24-hour window may contain promotional content." | S8 |
| Human agent allowance | "For a human agent response, the Human Agent feature allows replies within **7 days**." Allowed use is limited to cases the standard window cannot cover, such as a business closed for the weekend. | S9 |
| Human agent, platform scope | The Human Agent tag lets businesses respond "to user messages on Messenger **and Instagram** manually outside the 24-hour standard messaging window" for up to 7 days. | S7, entry dated **2021-06-02** |
| Human agent, Instagram-side naming | S1 refers to tagging a response so it can be sent "outside the 24 hour messaging window" for human agent experiences, but **the literal string `HUMAN_AGENT`, the parameter `messaging_type`, the value `MESSAGE_TAG` and the figure "7 days" do not appear on S1.** | S1 |
| Which tags apply | "Some message tags are available on both Messenger Platform and IG Messaging API." "Some message tags are available only for Messenger Platform and not IG Messaging API." "Use of tags outside of approved use cases may result in restrictions on your ability to send messages." **The policy page does not say which tags fall in which group.** | S8 |
| Private Replies and the tag | Private Replies no longer need the Human Agent tag; Human Agent tag calls for Private Replies stopped working after **2021-09-13**. | S7, deprecation dated 2021-08-06 |
| Click-to-Instagram thread control (not the messaging window) | A custom thread control window for Click To Instagram Ads: control lasts 24 hours from the last user message, extendable to **30 days** via `receiving_app_control_expiration`; invalid values reset it to **1 day**. S7 presents this as thread control, **not** as an extension of the messaging window. | S7, 2025-09-16 |

**Answer to the brief's question:** yes, a human-agent equivalent applies to Instagram, at **7 days**,
and 7 days is stated normatively on an Instagram Platform page (S9) and in a dated changelog entry that
names Instagram (S7). The exact Instagram request shape is **not checked** — see §6.

### 2.4 Restrictions Meta documents

- **Inbound-first.** No message may be initiated. (S1)
- **Requests folder, 30 days.** "Messages in the Requests folder that have not been active for 30 days will
  not be returned in API calls." (S1) S9 adds that messages from non-followers go to Requests and are not
  marked "Seen" until accepted, and S9 does **not** restate the 30-day figure.
- **Read state is not what an agent expects.** S9: webhook notifications and API-delivered messages do
  **not** count as "Read" in the Instagram inbox; a message becomes Read **only after a reply is sent**.
- **Folders.** S9: inbox folders are not supported, and messages delivered through the Messenger Platform
  carry no folder information. Replies sent through a third-party app **move the conversation to the General
  folder regardless of inbox settings**.
- **Ownership.** Shared posts and media must be owned by the app user / business. (S1, S12)
- **Story replies exclude GIFs and stickers.** S6: story replies "don't currently support GIFs or stickers".
- **Story media must not be cached.** S11: "You must not store or cache the media content on your server."
  Storing the **CDN URL** is permitted. S11 recommends either in-thread rendering or a placeholder behind a
  view button, and says that when the story expires or is deleted the URL stops rendering and the product
  should show a placeholder indicating the content is no longer available.
- **Promotional content.** The only promotional rule found that bears on Instagram is S8's permission for
  promotional content *inside* the 24-hour window. The "must not be used for promotional content" clause on
  S8 is scoped to news messaging on NPI-registered news Pages, **not** to Instagram generally. **No
  Instagram-specific promotional cap, opt-in requirement or per-user marketing limit was found on any page
  checked.** This is a gap, recorded in §6; it must not be filled from the WhatsApp marketing rules.
- **Bot responsiveness.** S8: "Automated bots must respond to user input within 30 seconds." S8 does not say
  whether this applies to Instagram.
- **Automated chat disclosure.** S9: where required by law (S9 names California and Germany), automated chats
  must disclose that the user is talking to an automated service.
- **Developer Policies apply.** S8: "Our Developer Policies apply to Messenger Platform and Instagram
  Messaging API."

### 2.5 Where Instagram differs from Messenger despite the shared Send API

This table is the core of any Instagram troubleshooting article. Every row is from a page that states the
difference, not from inference.

| Behaviour | Messenger | Instagram | Source |
|---|---|---|---|
| Identity of the customer | Page-scoped ID (PSID) | **Instagram-scoped ID (IGSID)**; Instagram User IDs are rejected | S2, S1, S4 (100–2534014) |
| Echo of outbound messages | separate `message_echoes` field — "This separate webhook field is available only for Messenger conversations." | **no separate echo field**; echoes arrive on `messages` with `is_echo` = `true` | S10, S6, S3 |
| Read receipts | `message_reads` | **`messaging_seen`** (payload `read.mid`) | S10, S6 |
| Delivery receipts | `message_deliveries` — "Only available for Messenger conversations." | **not available** | S10 |
| Message edits | `message_edits` — "Only available for Messenger conversations." But S7 (2025-09-10) announces a **`message_edit`** subscription **for Instagram**. The two pages conflict — see §6 | contested | S10 vs S7 |
| Account linking, feedback, game plays, send cart, `messaging_optins` | available | S10 marks each "Only available for Messenger conversations." | S10 |
| Handover | Handover Protocol | **deprecated for Instagram on 2025-10-23**; all businesses migrated to Conversation Routing, described as "mostly backward compatible" | S7 |
| One-time notification / sponsored messages / news messaging | available | **not available for IG Messaging API** | S8 |
| Rate-limit scope | per Facebook **Page** | per Instagram **Professional account** | S5 |
| Rolling daily cap | 200 × Number of Engaged Users over a rolling 24 hours | **no equivalent cap** in the Instagram section | S5 |
| High-volume cut-off | more than **40 messages per second**, or constant traffic across many conversations; fetching *all* conversations fails but single-conversation calls still work | more than **72,000 messages** sent+received (a **total count**, not a rate); new messages stop appearing in the Instagram Inbox and the account cannot send until volume drops; conversations show "Your Message May Be Delayed" / "Your Message Wasn't Delivered" banners | S5 |
| Daily call-count accounting | counted | S9: messaging endpoints are **excluded** from the app's 24-hour call count | S9 |
| Private Replies | 750/hour per Page for Instagram post and reel comments; no Live-comment limit listed | 750/hour for post and reel comments **plus 100 calls/second for Instagram Live comments** | S5 |
| Postback triggers | button clicks generally | Icebreaker option or Generic Template button | S10 |
| Inbound story semantics | n/a | story replies (`reply_to.story`) and story mentions (`story_mention`) exist, with a no-caching rule on the media | S6, S11 |
| Inbound media caching | no such rule found | **story media must not be stored or cached on your server** | S11 |
| Group threads | — | one customer per conversation | S1 |
| Prerequisite account shape | a Facebook Page | either an IG professional account linked to a Page (Messenger-API-for-Instagram route) or, since 2024-06-23, **no Page at all** via Instagram API with Instagram Login on `graph.instagram.com` | S7, S1 |

## 3. Error codes and failures

All rows are from **S4** unless the source column says otherwise. The "title" column reproduces Meta's own
message string. A cell reading `not stated` means S4 leaves it blank — nothing is inferred.

### 3.1 The Instagram-labelled family

S4 explicitly names Instagram or IG in these rows.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 100 | 2534013 | "The page is not linked to an Instagram account" | the Page ID used in the call has no linked IG professional account | use the ID of the Facebook Page linked to the IG professional account | nothing — send never leaves | S4 |
| 100 | 2534014 | "No matching Instagram user" | an Instagram User ID was passed where an IGSID is required | confirm an Instagram-scoped ID is used; Instagram User IDs are not accepted | nothing | S4 |
| 100 | 2534029 | "The business has been blocked from sending messages via the IG Messaging API" | a policy enforcement against the business | "Resolve any policy violations before sending messages through the Messenger Platform" | nothing; the business is silent to every customer | S4 |
| 100 | 2534077 | "Cannot verify the connection between the IG account, the logged in user and the page." | Page↔IG link broken, or two-factor authentication not enabled | have the user check the link, or unlink and relink the Page and IG account | nothing | S4 |
| 200 | 2534041 | "The account owner has disabled access to instagram direct messages." | the IG professional account owner revoked the app's access to DMs | the owner must re-enable third-party DM access | nothing | S4 |
| 36103 | none | "To onboard creator accounts during Instagram phased rollout" — eligibility check returns "This IG account is not eligible for API yet" | the account is not yet in the API rollout | call the Conversation API with the Page access token to test eligibility; wait | nothing | S4 |

### 3.2 Outside the window

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 10 | 2534022 | "This message is sent outside of allowed window." | the 24-hour window has closed | send only within 24 hours of the customer's last message; otherwise use the human agent allowance (§2.3) | nothing | S4 |
| 10 | 2018278 | "This message is sent outside of allowed window." (S4 links to a newer policy) | the same restriction under a newer policy | as above | nothing | S4 |
| 10 | 2018065 | outside window; requires News Messaging permission | sending outside the window under news messaging | not applicable to Instagram — S8 states news messaging is **not available** for IG Messaging API | nothing | S4, S8 |

2534022 is the Instagram subcode by range (O2); S4 does **not** label the 2534022 row Instagram, so an
article should present it as the code Instagram sends without asserting that Meta labels it so.

### 3.3 Cannot message this user / privacy and blocking

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 551 | none | "User Block Error: This person isn't receiving messages from you right now." | the recipient is not receiving messages from the business | nothing from the API side | the customer chose this; they see no message | S4 |
| 551 | 1545041 | "This person isn't available right now." | recipient unavailable | — | nothing | S4 |
| 200 | 1545041 | "Message Not Sent: This person isn't available right now." | the same condition reported as a send failure | — | nothing | S4 |
| 10 | 2018108 | "They can't receive your messages right now." | the recipient cannot currently receive messages. **S4 gives no solution for this row** | `not stated` | nothing | S4 |
| 2 | none | "An unexpected error has occurred. Please retry your request later." | S4 adds: "May also occur if the customer has blocked your business." | retry; if persistent, treat as a block | nothing | S4 |
| 100 | 2534037 | "The action is invalid since it's not the thread owner." | the app lacks permission for this action on the conversation | check permissions and access tokens; with Conversation Routing, check thread ownership | nothing | S4 |
| 200 | 2018028 / 2018027 | cannot message users who are not admins, developers or testers until permission review | the app is not live, or the messaging permission is not approved | complete app review for the messaging permission | nothing | S4 |
| 200 | 2018021 | requires phone matching access fee | applies unless the recipient is an app admin, developer or tester | — | nothing | S4 |

**There is no single "message blocked by user privacy settings" code.** Meta spreads the condition across
551, 551–1545041, 200–1545041, 10–2018108 and a caveat on code 2. An Instagram article must say that, and
must not claim a cause the API does not distinguish. Note also that S4 supplies **no solution text** for
10–2018108.

### 3.4 Unsupported or invalid message content

| Code | Subcode | Title as Meta words it | What it means | What the business can do | Source |
|---|---|---|---|---|---|
| 100 | 2534015 | "Invalid message data" | the data type is not allowed for that message type | confirm the data type is allowed for the message type being sent | S4 |
| 100 | 2534025 | "The comment is invalid for a private reply" | the private-reply payload's data type is not allowed | confirm the data type in the private reply | S4 |
| 100 | 2018047 | "Upload attachment failure." | often a media type that does not match the file at the URL | correct the declared type | S4 |
| 100 | 2018008 | "Failed to fetch the file from the url." | Meta could not retrieve the file | check URL, SSL certificate, file size and server response time | S4 |
| 100 | 2018109 | "Attachment size exceeds allowable limit" | over the size cap (§2.2) | resize or re-encode | S4 |
| 100 | 2018294 | video upload timed out or video is corrupted | "Videos not fetched within 75 seconds time out" | re-host, or use the Attachment Upload API and send `attachment_id` (S7, 2026-03-13) | S4, S7 |
| 100 | 2018074 | possibly invalid ID, or the app does not own the attachment | attachment ownership or ID problem | see the Attachment Upload API documentation | S4 |
| 100 | 2018014 | cannot send both message and state at the same time | `message` and `sender_action` in one call | send them separately | S4 |
| 100 | 2018320 | "Invalid product id" | product ID wrong or inaccessible | verify the product ID and the app's access | S4 |
| 100 | 2018328 | product template not supported below version 8 | API version too old | use **v8 or higher** | S4 |
| 100 | 33 | "Unsupported get request. Object with ID * does not exist, cannot" | object missing or not visible to the token | check the ID and the token's access | S4 |
| — | 2534068 | `not stated` on S4 | S7: accounts not yet enabled for Instagram multi-image sending "may receive error `2534068`" | wait for rollout, or send images singly | **S7 only** — this subcode was not found on S4 |

### 3.5 Policy refusals and restrictions

| Code | Subcode | Title as Meta words it | What it means | What the business can do | Source |
|---|---|---|---|---|---|
| 100 | 2534029 | "The business has been blocked from sending messages via the IG Messaging API" | Instagram-specific policy block | resolve the policy violations | S4 |
| 10 | 1893063 | "You are temporarily restricted from sending messages." | activity breaking the Messaging Policies | stop the offending pattern and wait out the restriction | S4 |
| 10 | 1404170 | "Application does not have permission for this action" | the Page is temporarily restricted from sending Marketing Message opt-in requests | — | S4 |
| 613 | 2018338 | warning about bothersome or abusive behavior | tag-send rate too high | "Significantly reduce the message-tag sending rate, or face messaging restrictions" | S4 |
| 2022 | none | commerce messaging temporarily disabled | a feature limit after a policy violation | — | S4 |
| 10 | 1893015 | "(#10) This user has currently stopped notification messages for this topic" | the user clicked "Stop these messages" for a Marketing Message topic | do not re-send on that topic | S4 |
| 10 | 2018336 | `not stated` (user-level thread impact) | code 10 with this subcode means the thread is impacted at user level | check with the User Level Menu API | S4 |

### 3.6 Rate limiting

| Code | Subcode | Title as Meta words it | What it means | What the business can do | Source |
|---|---|---|---|---|---|
| 613 | 2534040 | "Calls to this api have exceeded the rate limit." | the Instagram-range rate-limit refusal | pause API calls and retry later | S4 |
| 4 | none | "Rate Limit error: Application request limit reached." | app-level limit | pause requests until volume drops below the limit | S4 |
| 4 | 2018354 | minimum delay required between notifications | cadence too tight | "Can be ignored", but track cadence to exclude users from future broadcasts | S4 |
| 9 | 2018352 | "User is performing too many actions" | the Marketing Message opt-in limit was exceeded | — | S4 |

### 3.7 Authentication and the deleted-message code

| Code | Subcode | Title as Meta words it | What it means | Source |
|---|---|---|---|---|
| 190 | none | invalid OAuth token | the token expired or was invalidated | S4 |
| 9000001 | none | "This Message has been deleted by the user or the business." | returned when the message in question no longer exists because it was unsent. S4's solution column holds only "OAuthException" and **no guidance** | S4 |

**9000001 is the single most important code for the brief's unsend question**, and Meta documents no
remedy for it.

## 4. Limits and numbers

Only figures a source states. Each carries its row.

| Figure | Value | Scope | Source |
|---|---|---|---|
| Standard messaging window | 24 hours from the customer's last message | Instagram | S1, S8, S4 (10–2534022) |
| Human agent allowance | 7 days | Instagram | S9, S7 (2021-06-02) |
| Requests-folder retention in API results | 30 days of inactivity | Instagram | S1 |
| Text length | "1000 bytes or less" / "under 1000 characters" — **the same page states both** | Instagram | S1, S12 |
| Image size | 8MB, png/jpeg | Instagram | S1, S12 |
| Video size | 25MB (mp4, ogg, avi, mov, webm) | Instagram | S1, S12 |
| Audio size | 25MB (aac, m4a, wav, mp4) | Instagram | S1, S12 |
| File size | 25MB, PDF only | Instagram | S1, S12 |
| Attachments per message | up to 10 | Instagram | S1, S12 |
| Send API — text, link, reaction, sticker | **300 calls/second per Instagram professional account** | Instagram | S5; S7 (2024-10-08) records the raise "to 300 (up from 100)" |
| Send API — text, link, reaction, sticker (stale figure) | **100 calls/second** | Instagram | **S9 still prints 100.** S5 and S7 say 300. S9 is out of date — see §5 |
| Send API — audio and video | 10 calls/second per Instagram professional account | Instagram | S5, S9 |
| Send API — single thread | throttling possible; **no number given** | Instagram | S5 |
| Conversations API | 2 calls/second per Instagram professional account | Instagram | S5, S9 |
| Private Replies — Instagram Live comments | 100 calls/second | Instagram | S5, S9 |
| Private Replies — comments on posts and reels | 750 calls/hour | Instagram | S5, S9 |
| High-volume threshold | more than 72,000 messages sent and received (total count, not a rate) | Instagram | S5 |
| Video fetch timeout | 75 seconds | Send API | S4 (100–2018294) |
| Messenger rolling cap, for contrast | 200 × Number of Engaged Users per rolling 24 hours | **Messenger only** | S5 |
| Messenger high-volume threshold, for contrast | more than 40 messages/second | **Messenger only** | S5 |
| Click-to-Instagram thread control | 24 hours default, extendable to 30 days; invalid values reset to 1 day | Instagram | S7 (2025-09-16) |
| Bot response requirement | 30 seconds | S8 does not say whether this covers Instagram | S8 |

**Media / CDN URL expiry — what Meta actually states.** This matters because inbound Instagram media
reaches Lynomia only as a URL.

- **S9 (normative):** Instagram Platform "leverages Content Delivery Network (CDN) URLs" to deliver rich
  media, and such a URL **"won't return media once the content has been deleted or has expired."** S9 gives
  **no expiry period**.
- **S11 (normative, story media):** stories are temporary — "it disappears after 24 hours or when deleted by
  the user"; when that happens the URL stops rendering and the product should show a placeholder. S11 gives
  no separate validity period for the URL itself, and forbids storing or caching the media.
- **S6 (normative):** the Instagram webhook page **makes no statement at all** about CDN or attachment URL
  expiry.
- **O1 (observational, unconfirmed):** a Developer Community Forum reply states there are no permanent CDN
  URLs and that apps should cache the content themselves or re-query the object for a fresh URL. This is a
  forum reply, **not documentation**, and it also contradicts S11's no-caching rule for story media.

**Therefore: Meta documents no numeric expiry for inbound Instagram media URLs.** The only normative
statements are "privacy-aware; returns nothing once deleted or expired" (S9) and the story's own 24-hour
lifetime (S11). A Lynomia article must say exactly that and must not state a number.

## 5. Version and deprecation notes

| Date | Change | Version / impact | Source |
|---|---|---|---|
| 2026-04-27 | The legacy `share` attachment is being removed from Instagram post-share webhooks, rolling out gradually; once rollout reaches an app, "webhooks will return only the `ig_post` attachment". Apps may migrate or request exclusion through the developer support portal | **breaking for inbound post-share handling** | S7 |
| 2025-10-30 → 2026-02-01 | From 2025-11-03 post-share payloads include **both** `share` and the new `ig_post` attachment; `share` is supported "for Instagram posts until February 1, 2026", after which it will be removed | the two S7 entries give **different removal timelines** (2026-02-01 vs a gradual 2026-04-27 rollout) — see §6 | S7 |
| 2026-03-13 | The Instagram Direct Send API accepts attachment IDs as well as image URLs, addressing upload timeouts with large images; IDs are reusable across recipients | mitigates 100–2018294 and 100–2018008 | S7 |
| 2026-08-30 | Until this date, stickers are sent as **both** `sticker` and `image` attachment types | affects deduplication of inbound stickers | S2 |
| 2025-12-19 | PDF attachments can be sent in Instagram Direct; the Instagram Message Replies API allows replying to a specific message via the Graph API for Page-linked accounts | — | S7 |
| 2025-12-02 | Instagram Send API supports reacting with an emoji, editing a reaction, and removing a reaction | — | S7 |
| 2025-10-23 | **Handover Protocol is no longer supported for Instagram.** All businesses migrated to Conversation Routing, "mostly backward compatible" | **deprecation** | S7 |
| 2025-10-21 | Instagram Moderate Conversations API: block users, unblock users, move conversations to the spam folder | new capability | S7 |
| 2025-10-13 | Conversations API `is_owner` field applies to Messenger and Instagram; returned only when Conversation Routing is enabled | — | S7 |
| 2025-10-06 | `reply_to` available in the Conversations API and in Message and Echo webhooks, with `is_self_reply` | — | S7 |
| 2025-09-23 | Typing and `mark_seen` sender actions available | — | S7 |
| 2025-09-16 | Custom thread control window for Click To Instagram Ads | — | S7 |
| 2025-09-10 | New **`message_edit`** webhook subscription for Instagram, for both Business Login for Instagram and Facebook Login for Business | **conflicts with S10**, which says `message_edits` is Messenger-only | S7 vs S10 |
| 2025-11-03 | Multi-image sending (a collection of images) in Instagram Direct, Beta; accounts not yet enabled may receive error `2534068` | — | S7 |
| 2024-10-08 | Send API rate limit raised to "300 (up from 100) calls per second per Instagram professional account" for text, links, reactions and stickers | **S9 still prints 100** | S7 vs S9 |
| 2024-06-23 | Instagram API with Instagram Login: host `graph.instagram.com`, **no Facebook Page required**, permissions including `instagram_business_manage_messages` | two distinct integration routes now exist | S7, S1 |
| 2023-02-02 | GIF sending, Attachment Upload API support for Instagram, Click-to-Instagram referral data in the messages webhook | — | S7 |
| 2022-08-16 | Private Replies for Instagram Reels; audio and video message sending | — | S7 |
| 2022-05-19 | Send API limit raised to 100 calls/second | superseded by 2024-10-08 | S7 |
| 2022-11-09 | Persistent Menu available for Instagram Messaging | — | S7 |
| 2021-08-06 | Private Replies no longer need the Human Agent tag; such calls stopped working after 2021-09-13 | **deprecation** | S7 |
| v12.0 | Extended reaction types (`angry`, `sad`, `wow`, `love`, `like`, `laugh`, `other`) | inbound reaction parsing is version-dependent | S6 |
| v11.0 | `mid` added to postbacks | — | S6 |
| v8.0 | postbacks | — | S6 |
| v8+ | product templates require API version 8 or higher | S4, 100–2018328 | S4 |
| v25.0 | the version in current Instagram Platform samples (S1, S3) | — | S1, S3 |

## 6. Ambiguities and gaps

These are recorded, not resolved. Several require Agent 028 or 090 to arbitrate, and none may be filled in
by guessing.

1. **Voice notes are undocumented as a type.** No page checked says how an Instagram voice note arrives.
   `audio` with a `payload.url` (S6) is the plausible shape, but Meta does not say so, and `ephemeral` with
   no URL (S6) is also possible for a disappearing voice clip. **Unverified.** Resolving it needs either a
   Meta page that names voice notes or a controlled observation in a non-production inbox.
2. **Text length contradicts itself inside one page.** S12's basic-message section says "1,000 bytes or
   less"; S12's Limitations section says "under 1000 characters". For non-Latin text — Arabic, which Lynomia
   serves — these are very different limits. Meta does not reconcile them.
3. **`message_edit` / `message_edits` for Instagram.** S10 states `message_edits` is "Only available for
   Messenger conversations"; S7 (2025-09-10) announces a `message_edit` subscription **for Instagram**. The
   field name also differs between pages. Unresolved.
4. **Two different removal timelines for the `share` attachment.** S7's 2025-10-30 entry says `share` is
   supported until **2026-02-01**; S7's 2026-04-27 entry describes a **gradual rollout** of its removal with
   an exclusion request path. Today is 2026-10-13, after both dates, so the practical state of `share` is
   **unverified without observation.**
5. **The exact Instagram human-agent request shape is not checked.** S9 and S7 establish *7 days* and that
   it applies to Instagram. Neither the Instagram Human Agent Escalation page nor the Messenger message-tags
   page returned body content, so `messaging_type: MESSAGE_TAG` + `tag: HUMAN_AGENT`, and the permission
   required, are **not confirmed from an Instagram source**. An article must not print the parameter names
   as Instagram-documented until one of those pages is read.
6. **Which message tags are valid on Instagram is nowhere enumerated.** S8 says some tags work on both and
   some only on Messenger, and does not list either set. This is a real gap in Meta's documentation.
7. **No Instagram-specific promotional or marketing limit was found.** S8 permits promotional content inside
   the 24-hour window and otherwise scopes its promotional prohibition to news messaging. There is no
   Instagram equivalent of WhatsApp's marketing-message caps and per-user limits on any page checked. Do not
   import the WhatsApp rules.
8. **No numeric expiry for inbound media URLs.** §4 covers this. The only normative statements are
   "privacy-aware" and the story's 24-hour lifetime.
9. **The 2534xxx range is only partly labelled.** S4 names Instagram on 2534013, 2534014, 2534029, 2534041,
   2534077 and 36103, but **not** on 2534015, 2534022, 2534025, 2534037 or 2534040 — even though those are
   the codes an Instagram integration hits most. Treating the whole range as Instagram is O2, an inference.
10. **S4 has no solution text for 10–2018108**, and only "OAuthException" for **9000001**. Both are codes a
    support desk will be asked about.
11. **`messaging_reactions` vs `message_reactions` vs a top-level `reaction` key.** S6 names the event field
    `message_reactions` while putting the data under `reaction`; S3 lists `message_reactions`; the earlier
    search surfaced `messaging_reactions`, which **does not appear** on S3. The subscription field name is
    ambiguous across Meta's own pages.
12. **Whether S8's 30-second bot-response requirement applies to Instagram** is not stated.
13. **Lynomia's code cites error 9010 "No matching Instagram user" with `type: IGApiException`**
    (`app/services/instagram/message_text.rb:55-58`), while S4 documents that exact message string as
    **100 – 2534014**. Whether 9010 is a separate live code or a historical one is **unverified** — it does
    not appear on S4. Flagged for Agent 028.

## 7. What Lynomia users would ask

### 7.1 Message unsend — the question the brief singles out

**What Meta delivers.** When a customer deletes an Instagram message, Meta sends a `messages` webhook whose
`message.is_deleted` is `true` (S6). The payload carries the `mid` and nothing else: **no text, no
attachment, no reason, and no statement of who deleted it.** Separately, S4 documents code **9000001 — "This
Message has been deleted by the user or the business."** — with no remedy, which is what an API call about a
vanished message returns.

**What Lynomia does.** `app/services/instagram/base_message_text.rb:41-42` detects
`@messaging[:message][:is_deleted]`, and `:20` short-circuits the normal path to `unsend_message` before any
contact or message is created. `unsend_message` at `:51-59` finds the stored message by
`source_id == @messaging[:message][:mid]`, calls `attachments.destroy_all`, then
`update!(content: I18n.t('conversations.messages.deleted'), deleted: true)`. If no stored message matches
the `mid`, `:55` returns and nothing is recorded at all.

**What Lynomia can honestly show.** This, and no more:

- That the message was deleted, and that it was deleted **on Instagram, by the participant** — because the
  only trigger is Meta's own `is_deleted` flag.
- The deleted message's **position in the thread**, since the row survives with `deleted: true`.
- That **the original content is gone and not recoverable in Lynomia** — `attachments.destroy_all` and the
  overwrite of `content` at `:57-58` are destructive. The prior text is not retained anywhere in that path.

What Lynomia must **not** claim: a timestamp of the deletion distinct from the webhook's arrival, a reason,
a distinction between "the customer deleted it" and "the business deleted it" (Meta's own 9000001 string
covers both and the webhook names neither), or a recoverable copy. And if Lynomia never stored the original —
a webhook missed, or a message that arrived before the inbox existed — the deletion event leaves **no trace
whatsoever**, because `:55` returns early. An honest article says: *we show that something was deleted where
we had already stored it; we cannot show what it said, and if we never received it, we cannot show that it
existed.*

### 7.2 A compliance finding worth escalating

S11 states plainly: **"You must not store or cache the media content on your server."** Lynomia's Instagram
story handling does exactly that. `app/builders/messages/instagram/base_message_builder.rb:118-130` creates
an attachment with `file_type: :ig_story` and `external_url: story_url`, then calls
`attach_file(attachment, story_url)` at `:128` — downloading the story media into Lynomia's own storage, with
only a `Rails.logger.warn` on failure at `:130`. Storing the **CDN URL** (as `external_url` does) is
permitted by S11; downloading the media is not. This is an Agent 000 arbitration item, not a documentation
item, and it is the reason the help content cannot simply promise "story replies always show the story".

### 7.3 The questions this area produces for a support desk

| The user's question | What the answer has to contain | Source |
|---|---|---|
| "Why can't I message this Instagram customer first?" | Instagram permits no initiation; the customer must message the professional account first | S1 |
| "The reply failed and I don't know why." | distinguish 10–2534022 (window closed) from the privacy/block family (551, 551–1545041, 200–1545041, 10–2018108, code 2) — the API does **not** always distinguish | S4 |
| "Can we follow up after a day?" | 24-hour standard window; a human-agent response is allowed within 7 days, for cases the standard window cannot cover | S1, S9 |
| "Why did the story in this reply disappear?" | stories last 24 hours or until deleted; the CDN URL then stops returning media; the product shows a placeholder | S11, S9 |
| "Why is the image in this message broken?" | inbound media is a privacy-aware CDN URL that returns nothing once the content is deleted or expired; Meta publishes no lifetime | S9 |
| "Why does Instagram still show this conversation as unread after we replied through Lynomia?" | webhooks and API delivery do not mark Read; a message becomes Read only after a reply is sent, and a third-party reply moves the thread to the General folder | S9 |
| "Where did the conversation go in the Instagram app?" | replies via a third-party app move it to General regardless of inbox settings; folders are not supported over the API | S9 |
| "A customer deleted a message — what happened?" | §7.1 | S6, S4 |
| "Why is this message 'unsupported'?" | `is_unsupported` = true, or an `ephemeral` attachment with no URL; the content is never delivered | S6 |
| "The account owner revoked something and now nothing sends." | 200–2534041 and 100–2534077 | S4 |
| "We're rate limited." | 613–2534040, plus the per-account figures (300/s text, 10/s audio-video, 2/s Conversations) and the 72,000-message high-volume state with its Instagram Inbox banners | S4, S5 |
| "Why does our Messenger setup work and Instagram not?" | §2.5 in full, especially echo-on-`messages`, `messaging_seen`, no delivery receipts, handover deprecated, IGSID not PSID | S10, S6, S7 |
| "Can we send a promotion?" | permitted inside the 24-hour window; sponsored messages, one-time notifications and news messaging are **not available** on IG; no Instagram-specific promotional cap is documented | S8 |
| "Can we send a GIF or sticker as a story reply?" | story replies do not support GIFs or stickers | S6 |
| "Why didn't we get a webhook when a customer tagged us in a post?" | only story mentions fire a webhook; post tags do not. Story mentions also require the mentioning account to be public, or private and following the professional account | S6, S11 |
| "Can we message a group?" | no — one customer per conversation | S1 |
| "An old request thread isn't there." | Requests-folder messages inactive for 30 days are not returned by the API | S1 |
