---
agent: 022
scope: Messenger Platform — Send API, messaging types, message tags, the messaging window, handover protocol, messaging webhook fields, Messenger error codes
confidence: medium
sources_normative: 10
sources_observational: 1
---

# Agent 022 — Messenger Platform

Lynomia ships a Messenger integration with **zero** documentation articles. This report is the entire normative
basis for that section. Everything below is traceable to a row in §1. Where Meta does not state something, the
cell says `not stated`; where I could not retrieve the page, §6 says so plainly.

**Method and honesty notes.** All facts come from pages I fetched and read on `developers.facebook.com` on
2026-10-13. Two `WebSearch` calls were used **only to discover URLs** — no search-engine summary is used as a
source anywhere in this report. Four Meta pages that are in scope could not be retrieved (§6.1): they return
only site chrome (client-side rendered) or 404. **No code, tag name, subcode or numeric limit in this report is
invented.** One important mechanical caveat: the fetch tool truncated long quoted error strings at 125
characters and marked them `…`. Any error message below ending in `…` is **incomplete** — do not ship it to a
user or match on it as a full string without re-reading the source page.

---

## 1. Source register

| Row | Source URL | Page title | Product | API/version context | Date checked | Class |
|---|---|---|---|---|---|---|
| R1 | https://developers.facebook.com/docs/messenger-platform/send-messages/ | Send a Message | Messenger Platform | none stated | 2026-10-13 | normative |
| R2 | https://developers.facebook.com/docs/messenger-platform/reference/send-api/error-codes/ | Common Error Codes | Messenger Platform | none stated | 2026-10-13 | normative |
| R3 | https://developers.facebook.com/docs/messenger-platform/webhooks/ | Meta Webhooks for Messenger Platform | Messenger Platform | none stated | 2026-10-13 | normative |
| R4 | https://developers.facebook.com/docs/messenger-platform/changelog/ | Messenger Platform Changelog | Messenger Platform | latest listed v26.0 | 2026-10-13 | **observational** (changelog) |
| R5 | https://developers.facebook.com/docs/messenger-platform/reference/webhook-events/standby/ | standby Webhook Event Reference | Messenger Platform | none stated | 2026-10-13 | normative |
| R6 | https://developers.facebook.com/documentation/business-messaging/messenger-platform/policy | Messenger Platform and IG Messaging API policy | Messenger Platform / IG Messaging | none stated | 2026-10-13 | normative |
| R7 | https://developers.facebook.com/docs/graph-api/reference/page/messages/ | Graph API Reference v26.0: Page Messages | Graph API | **v26.0** | 2026-10-13 | normative |
| R8 | https://developers.facebook.com/docs/messenger-platform/send-messages/quick-replies/ | Quick replies | Messenger Platform | none stated | 2026-10-13 | normative |
| R9 | https://developers.facebook.com/docs/messenger-platform/send-messages/template/generic/ | Generic template | Messenger Platform | examples use **v25.0** | 2026-10-13 | normative |
| R10 | https://developers.facebook.com/docs/messenger-platform/reference/webhook-events/messaging_handovers/ | messaging_handovers Webhook Event Reference | Messenger Platform | none stated | 2026-10-13 | normative |
| R11 | https://developers.facebook.com/docs/messenger-platform/reference/handover-protocol/ (redirects to the reference index) | Reference Documentation | Messenger Platform | none stated | 2026-10-13 | normative (index only, two one-line field descriptions) |

**Classification note for Agent 000 / 028.** Program §6.2 lists Meta's changelog pages among the normative
source set, but the same paragraph classes "a changelog" as *observational*. I have resolved this by treating
R4 as **observational** and never letting a changelog entry be the sole basis for a rule a user is told to rely
on. Two of the most consequential facts in this report — the April 2026 tag deprecation and the removal of the
primary/secondary role requirement — currently rest on R4 alone. Agent 000 should decide whether that is
publishable as normative. See §6.2.

---

## 2. The rules

### 2.1 The Send API surface

The send endpoint is `POST /{page_id}/messages` (R7). R7 states explicitly that no Graph object is created, and
that read, update and delete are not supported on this edge. The success return is a struct of `recipient_id`,
`message_id` and `attachment_id` (R7).

R7 is the only page I could retrieve that enumerates the request parameters. Its parameters are:

| Parameter | Type | Allowed values / shape (verbatim from R7) |
|---|---|---|
| `messaging_type` | enum | `RESPONSE`, `UPDATE`, `MESSAGE_TAG`, `UTILITY` |
| `tag` | message tag | `ACCOUNT_UPDATE`, `CONFIRMED_EVENT_UPDATE`, `CUSTOMER_FEEDBACK`, `HUMAN_AGENT`, `POST_PURCHASE_UPDATE` |
| `recipient` | object, **required** | `id` (numeric string, required), plus `follow_id`, `story_id`, `poll_response_id`, `phone_number`, `name` (`first_name`, `last_name`), `user_ref`, `comment_id`, `post_id`, `player_id`, `one_time_notif_token`, `notification_messages_token`, `login_id` |
| `message` | object | `text`, `fallback_text`, `a2ui` (`text`, `dynamic_text`), `attachment` (`type`, `payload`), `attachments`, `quick_reply_type`, `quick_replies` (`content_type`, `title`, `image_url`, `data`, `payload`), `template` (`name`, `language.code`, `components`, `parameters`), `metadata` |
| `notification_type` | enum | `REGULAR`, `SILENT_PUSH`, `NO_PUSH` — default `REGULAR` |
| `sender_action` | enum | `MARK_SEEN`, `TYPING_ON`, `TYPING_OFF`, `REACT`, `UNREACT` |
| `persona_id` | numeric string | "The ID for your business persona" |
| `reply_to` | object | `mid` (string) |
| `payload` | string | payload of the sender action |

R7 describes `tag` (in one of its two parameter blocks) as "The use case tag of the message to bypass the
subscriptions permission check".

**R7 renders its parameter section twice and the two copies disagree** (see §6.3). The second copy is the
Messenger/Page-shaped one and is the basis for the table above. The first copy adds `thread_control`
(`app_id`, `control_type`, `metadata`), a `folder` enum whose only value is `PARTNERSHIP`, and a different
`recipient` shape (`id`, `email`, `ids`, `thread_key`, `google_chat_options`, `slack_options`); its return
struct adds `thread_key` and `gchat_space_name`. Those fields belong to a wider Business Messaging surface,
not to a Page/Messenger send. **Lynomia should not build against the first copy.** Recorded as an ambiguity,
not resolved.

### 2.2 Message types that can be sent

R1 lists the content types a business can send as: **audio, buttons, files, menus, GIFs, images, stickers,
templates, text, videos**. R1 does **not** mention quick replies or sender actions; both are documented on
their own pages (R8, and the `sender_action` enum in R7). R1's only guidance on text and images is
qualitative — "Keep it short", "Pay attention to quality" — it states no character or byte limits at all.

**Quick replies** (R8). A `quick_replies` array is added to the `message` object; the message must also carry
`text` or `attachment`. Each `quick_reply` object has:

- `content_type` — must be one of `text`, `user_phone_number`, `user_email`. R8's words: `text` "sends a text
  button"; `user_phone_number` "sends a button allowing recipient to send the phone number associated with
  their account"; `user_email` "sends a button allowing recipient to send the email associated with their
  account".
- `title` — required when `content_type` is `text`; **20 character limit**.
- `payload` — required when `content_type` is `text`; **1000 character limit**; may be an empty string if
  `image_url` is set.
- `image_url` — optional; "Image should be a minimum of 24px x 24px"; larger images are cropped and resized
  automatically.

A maximum of **13** quick replies is supported, shown above the composer. When a button is tapped the buttons
are dismissed and the button's title is posted as a message. On the webhook side a `messages` event arrives
whose `text` equals the tapped title, and the `message` object carries a `quick_reply` field containing the
`payload`. For the phone and email content types the value lands in the `payload` attribute and also in
`text`. R8 states two limits that matter operationally: if the person's profile holds no phone number or
email the quick reply **is not shown**, and tapping it does **not** grant any ongoing permission to read that
information later.

**Generic template** (R9). Still current — R9 carries no deprecation notice, though it does not state a status
either, and its examples call `v25.0` while R7 is `v26.0`. Shape:
`message.attachment.type = "template"`, `payload.template_type = "generic"`, `payload.elements = [...]`.
Each element takes `title` (**80 character limit**), optional `subtitle` (**80 character limit**), optional
`image_url`, optional `default_action` (same properties as a URL button except `title`), and optional
`buttons` (**maximum 3 per element**). `payload.elements` allows a **maximum of 10 elements**; multiple
elements render as a horizontally scrollable carousel. `payload.sharable` is an optional boolean, default
`false`, that enables Messenger's native share button. R9 states at least one property beyond `title` must be
set. R9 does **not** enumerate the full button type set — its examples use `web_url` and `postback` and it
links out for the rest, so the complete button enum is a gap (§6.2).

**Attachments.** The Attachment Upload API reference could not be retrieved (§6.1), and no page I read states
a maximum attachment size. The limit exists — R2 documents error `100 / 2018109` *"Attachment size exceeds
allowable limit"* — but **the number is unknown to this report and must not be invented.** What I can state
from R2 about attachment behaviour: a URL-sourced attachment fails with `100 / 2018008` when the URL is
invalid, lacks a valid SSL certificate, has a bad file size, or the server is too slow; `100 / 2018047`
"Upload attachment failure" is often caused by a declared media type that does not match the file at the URL;
and video has a hard fetch deadline — `100 / 2018294` fires when a video "wasn't fetched within 75 seconds, or
the file is corrupt".

### 2.3 Messaging types and what each permits

R7 gives the enum; R1 gives the meaning. The two use different names for the third value, which matters when
writing help copy.

| `messaging_type` (R7) | R1's name and rule |
|---|---|
| `RESPONSE` | "Response" — the message responds to a received message. May contain promotional **and** non-promotional content, and "must be sent during the standard messaging window." |
| `UPDATE` | "Updates" — sent proactively, not in reply to a received message. May contain promotional and non-promotional content, but "must also fall within the standard messaging window." |
| `MESSAGE_TAG` | "Tagged Message" — sent **outside** the standard messaging window. "must include a message tag that matches the allowed use case for the tag and contains non-promotional content." |
| `UTILITY` | **`not stated`** — the value appears in R7's enum but neither R7 nor R1 describes it. See §6.2. |

R1 never uses the literal string `MESSAGE_TAG`; it writes "Tagged Message" and "message tags" in prose. The
literal enum value is R7's. Any Lynomia article must give the API value, because that is what the integration
sends and what an error will be about.

The practical consequence for an inbox: `RESPONSE` and `UPDATE` **differ in intent but not in window** — both
require the standard messaging window. Choosing `UPDATE` does not buy extra time. Only a tag does.

### 2.4 The standard messaging window

R1 defines it as "the 24 hour time period in which you are allowed to send a message to a person". The clock
starts when the person messages your Page or Instagram Professional account, **or** starts a conversation
through a web plug-in (R1). R6 states the business side of the same rule: "Businesses have up to 24 hours to
respond to a user."

Inside the window, promotional content is permitted — R6: "Messages sent within the 24-hour window may contain
promotional content."

Outside the window, R6 names exactly three routes: **message tags**, **one-time notifications** (Messenger
only), and **sponsored messages** (Messenger only). Sponsored messages may carry promotional and
non-promotional content and must comply with advertising policies (R6).

No page I read states whether the window is reset by every inbound message or only by the first, nor what
happens at the exact boundary. Recorded as an ambiguity (§6.2).

### 2.5 The HUMAN_AGENT tag and its longer window

The tag value is `HUMAN_AGENT` (R7, in the `tag` enum). R1 and R6 both call it "the Human Agent tag" in prose
rather than by its API value.

- **What it permits.** R1: it "allows a business representative to manually respond to a person's messages
  within a 7-day period." R6: it lets businesses "manually respond to user messages within a 7-day period."
  R4 (changelog, 2021-06-02): it allows responses "outside the 24-hour standard messaging window up to 7days".
- **What Meta requires to use it.** R4 (2021-06-02) states developers must **apply for the Human Agent
  permission in the App Dashboard**, and that the tag became available to all developers on that date. This is
  the single most important operational fact in this section and it currently rests on an **observational**
  source — neither R1, R6 nor R7 states the permission requirement. Flagged in §6.2 as needing confirmation
  from the Send API reference (which I could not retrieve) before Lynomia publishes it as a requirement.
- **Human, not automated.** The three pages consistently frame it as a *business representative* /
  *manually respond* mechanism. No page I read gives an enforcement mechanism that detects automation, but the
  wording is the basis on which misuse would be judged.
- **Instagram.** R7 states that of the five tag values, **only `HUMAN_AGENT` is available for Instagram
  Messaging**.
- **Private replies no longer need it.** R4 (2021-08-06): private replies no longer require the Human Agent
  tag, and private reply calls using that tag "will stop working after Sept 13, 2021."

For Lynomia this is the whole basis of a human-staffed Messenger inbox: an agent replying to a customer 30
hours after the customer's last message can only do so with `messaging_type: MESSAGE_TAG` and
`tag: HUMAN_AGENT`, and only if the app holds the Human Agent permission.

### 2.6 Message tags Meta currently documents

This is the area where Meta's own pages contradict each other, and getting it wrong in a help article would
be actively harmful. Here is exactly what each source says.

**R7 (Graph API v26.0 Page Messages, normative) lists five tag values:**
`ACCOUNT_UPDATE`, `CONFIRMED_EVENT_UPDATE`, `CUSTOMER_FEEDBACK`, `HUMAN_AGENT`, `POST_PURCHASE_UPDATE`.

**R4 (changelog, observational, entry dated 2026-03-27) states that three of those five are deprecated:**
requests containing `CONFIRMED_EVENT_UPDATE`, `ACCOUNT_UPDATE` or `POST_PURCHASE_UPDATE` return **error code
100**, effective **2026-04-27**, with the error text "deprecated message tags are no longer allowed in API
Requests." R4 directs developers to migrate to **Utility Templates** or the **Marketing Messages API**.

**R6 (policy, normative) names a sixth tag** not present in R7's enum: `NON_PROMOTIONAL_SUBSCRIPTION`, usable
only by Pages registered in the News Page Index, for news messaging, non-promotional content only.

Reconciled picture as of the date checked (2026-10-13 — **five and a half months after the stated deprecation
date**):

| Tag (verbatim) | What Meta says it is for | Status as of 2026-10-13 | Source |
|---|---|---|---|
| `HUMAN_AGENT` | A business representative manually responds to a person's message, outside the 24-hour window, within 7 days. Requires the Human Agent permission. Only tag available for Instagram Messaging. | **Live** | R1, R6, R7, R4 |
| `CUSTOMER_FEEDBACK` | `not stated` on any page I retrieved. Present in R7's enum; R7 gives no per-tag description, and the message-tags page could not be retrieved. | **Live** (in enum, not listed as deprecated) | R7 |
| `NON_PROMOTIONAL_SUBSCRIPTION` | News messaging by News Page Index-registered Pages. Non-promotional only; must not carry subscription offers, deals, coupons or discounts. | **Live, restricted to news Pages** | R6 |
| `ACCOUNT_UPDATE` | `not stated` on any page I retrieved. | **Deprecated** — error 100 effective 2026-04-27 | R7 (enum), R4 (deprecation) |
| `CONFIRMED_EVENT_UPDATE` | `not stated` on any page I retrieved. | **Deprecated** — error 100 effective 2026-04-27 | R7 (enum), R4 (deprecation) |
| `POST_PURCHASE_UPDATE` | `not stated` on any page I retrieved. | **Deprecated** — error 100 effective 2026-04-27 | R7 (enum), R4 (deprecation) |

**Two things I am deliberately not doing here.** I am not writing per-tag use-case descriptions for the four
tags where no page I retrieved states one — the message-tags page is the page that carries them and it is not
retrievable (§6.1). And I am not asserting that only three tags remain, because R7, a normative v26.0
reference, still lists all five with no deprecation marker. That conflict is a **blocker for publication**
(§6.3, C1).

**Policy on tag misuse** (R6, normative). Tags exist for "personally relevant 1:1 updates to users outside the
24-hour standard messaging window" and are limited to approved use cases: "Use of tags outside of approved use
cases may result in restrictions on your ability to send messages." Sending tags too frequently has its own
error — `613 / 2018338` (§3).

### 2.7 Handover protocol

An inbox product competing for a thread with a bot, with Page Inbox, or with another partner app, lives or
dies on this. What I could retrieve is the **webhook/receive side in full** and the **send side not at all**.

**Roles.** R10 documents `app_roles`, sent "when a page admin changes your app's role", with the two roles
`primary_receiver` and `secondary_receiver`. R4 (2021-09-14 / 2022-03-14) says the September 2021 revision
included "removing the requirement to assign primary or secondary roles for apps". So a normative reference
page still documents the roles while an observational changelog says the requirement was removed. Both are
recorded; neither is resolved (§6.3, C2).

**`messaging_handovers` webhook sub-events** (R10). R11 summarises the field as "The ownership of a
conversation has changed from one app to another."

| Sub-event | When Meta sends it | Payload fields (verbatim) |
|---|---|---|
| `pass_thread_control` | Thread ownership for a user is passed **to** your application. | `new_owner_app_id`, `previous_owner_app_id` (**may be null in idle mode**), `metadata` |
| `take_thread_control` | Thread ownership is taken **away from** your application. | `previous_owner_app_id` (**may be null if the thread was idle**), `new_owner_app_id`, `metadata` |
| `request_thread_control` | Sent to the **Primary Receiver** app when a **Secondary Receiver** app calls the Request Thread Control API. The Primary Receiver may pass control or ignore the request. | `requested_owner_app_id`, `metadata` |
| `app_roles` | A page admin changes your app's role. | R10's example keys roles by app ID, e.g. `"123456789":["primary_receiver"]`; its properties table instead lists an `id` field described as "Your Page ID" — the two do not match (§6.3, C4). |

Every `messaging_handovers` event carries `sender.id` (the Page-scoped ID, PSID), `recipient.id` (your Page
ID) and `timestamp` (R10). R10's `app_roles` example shows a PSID in `recipient.id`, conflicting with its own
table description of that field as the Page ID — a documentation defect worth knowing before writing a parser.

**Note the asymmetry in `request_thread_control`:** a secondary receiver can *ask*, and the primary receiver
is free to ignore. There is no documented guarantee a request is honoured. An inbox that shows an agent a
"take over this conversation" button must not promise success.

**The standby channel — what a secondary receiver actually receives** (R5, normative; this is the clearest
page in the whole set). The `standby` callback fires "when a message has been sent to your page, but your
application is not the current thread owner". Normally events arrive on the `messaging` channel; standby
events arrive on the **`standby`** channel instead, and you subscribe by selecting the `standby` field when
setting up the webhook (R5; R11 describes `standby` as "A Page receives a message but the app is not the
current owner of the conversation").

Exactly four event types are delivered on standby (R5):

- `messages`
- `message_reads`
- `message_deliveries`
- `messaging_postbacks`

Payload shape (R5): top level `object` (example value `page`) and `entry`, an array. Each `entry` item has
`id` (the Page ID), `time`, and `standby` — "Array of messages received in the standby channel". Each standby
item includes `sender` (with `id`) and `recipient` (with `id`). R5's property definitions: `id` is "the PSID
of the user that triggered the event"; `time` is the "Timestamp of the message send". R5 also notes you can
receive message, read and delivery events through history messages.

**The single most important standby fact:** standby `messaging_postbacks` events **do not include the postback
payload** (R5). The app that originally sent the postback button receives the normal `messaging_postbacks`
event, which does include the payload. So a Lynomia inbox observing a thread it does not own will see *that*
a button was tapped but not *which* button — it cannot reconstruct the bot's state from standby alone.

**Exclusive mode and Idle mode.** R4 names both as part of the September 2021 revision but **does not define
either**. R10's "may be null in idle mode" is the only substantive mention of idle mode in anything I read.
Definitions are a gap (§6.2).

**Conversation Routing — the successor mechanism** (R4, observational). This is where Meta has been moving,
and an inbox product needs to know it exists:

| Date (R4) | Change |
|---|---|
| 2021-09-14 | Handover Protocol improvements announced; developers required to implement changes by 2022-03-01. |
| 2022-03-14 | Pages migrated to the new behaviour, completion expected by 2022-03-18. Improvements: Exclusive mode, Idle mode, new thread-ownership APIs, and removing the primary/secondary role assignment requirement. |
| 2023-09-12 | Conversation Routing introduced — routing rules defining which partners control conversations, managed in **Page settings**. |
| 2023-10-17 | Conversation Routing made available for Instagram. |
| 2024-06-11 | App-level thread control takeover configs became available; the original coupled config deprecated. |
| 2025-07-22 | Custom thread control window for Click to Messenger Ads: "the app controls the thread for 24 hours from the last user message", extendable **up to 30 days**. |
| 2025-09-16 | Same custom window for Click to Instagram Ads, using `receiving_app_control_expiration`. |
| 2025-10-13 | `is_owner` field added to the Conversations API for Messenger and Instagram; returned **only** when Conversation Routing is enabled. |
| 2025-10-23 | "Meta no longer supports the Handover Protocol for Instagram." All businesses moved to Conversation Routing, described as mostly backward compatible. |

The 2025-10-23 entry is directly relevant to Lynomia: **handover protocol is gone for Instagram** and that
section of the docs must not tell an Instagram user to use it. Hand this to Agents 023 and 024.

### 2.8 Webhook fields a Page app can subscribe to

R3 lists **19** subscribable Messenger Platform fields. Applicability is given where R3 states it.

| Field (verbatim) | Applies to | What it delivers |
|---|---|---|
| `messages` | Messenger and Instagram | Your business has received a message from a customer, from any entry point. For Instagram it also includes messages your account sent. |
| `message_echoes` | Messenger only | Your business has sent a message. For Instagram, echoes arrive under `messages`. |
| `message_deliveries` | Messenger only | A message your business sent has reached the customer. |
| `message_reads` | Messenger | A customer has read a message your business sent. |
| `messaging_seen` | **Instagram only** | A customer has read a message your business sent. |
| `message_edits` | Messenger only | A customer has edited a message they previously sent. |
| `message_reactions` | not specified | A customer has reacted to a message your business sent. |
| `messaging_postbacks` | Messenger and Instagram | A customer clicked a postback, Get Started, or persistent menu button (Messenger), or an Icebreaker or Generic Template button (Instagram). |
| `messaging_handovers` | not specified | A change has occurred during the Handover Protocol. |
| `standby` | not specified | A conversation has been idle for the app during the Handover Protocol. |
| `messaging_optins` | Messenger only | A customer opted in through a Messenger plugin, accepted a message request via customer matching, or used the checkbox plugin. |
| `messaging_referrals` | not specified | A customer resumed a conversation through an ig.me or m.me link, or through an ad. |
| `messaging_account_linking` | Messenger only | A customer linked or unlinked their Messenger account from their account with your business. |
| `messaging_feedback` | Messenger only | A person submitted feedback for your business. |
| `response_feedback` | not specified | A customer gave feedback on a message using the feedback buttons. |
| `messaging_policy_enforcement` | not specified | A policy warning or enforcement action has been taken against the app linked to the Page. |
| `messaging_game_plays` | Messenger only | A person played a round of an Instant Game. |
| `messenger_template_status_update` | not specified | A utility message template's review status has changed. |
| `send_cart` | Messenger only | A customer sent a message containing cart or order information. |

Three of these deserve Lynomia's attention beyond the obvious four:

- **`messaging_policy_enforcement`** is how Meta tells the app that a warning or enforcement action has landed.
  An inbox product that does not surface this leaves an admin to discover a restriction by failing to send.
- **`standby`** must be subscribed explicitly, or a non-owning app sees nothing (R5).
- **`message_reads` vs `messaging_seen`** split by platform: Messenger read receipts and Instagram read
  receipts arrive on **different fields**. Note that R3's own table labels the Messenger one `messaging_reads`
  in one place while the field name is `message_reads` — a defect in R3 (§6.3, C3).

**Subscribing.** `POST /<PAGE_ID>/subscribed_apps?subscribed_fields=<FIELDS>` with the Page access token;
`GET` on the same edge returns which apps are subscribed (R3). Via UI: Products → Messenger → Settings, enter
the Callback URL and Verify Token, subscribe to fields, Save. R3 also notes the app must be connected to the
Page in Meta Business Suite under All Tools → Business Apps, and warns: "You will need to subscribe all
messaging apps for your business to the messaging webhooks."

**Verification and signing** (R3). Meta sends a `GET` with `hub.mode=subscribe`, `hub.verify_token` and
`hub.challenge`; the endpoint must check the token against the configured Verify Token and return the
`hub.challenge` value, or return `403 Forbidden` on mismatch. Valid TLS/SSL required; self-signed certificates
are not supported. Payloads are signed SHA256 in the **`X-Hub-Signature-256`** header using the App Secret,
and R3 recommends validating against the **escaped Unicode form** of the payload. The endpoint must respond
`200 OK` **within 5 seconds**; failed deliveries are retried, and a Webhooks Disabled alert is sent if
delivery fails for **one hour**. (Agent 026 owns webhooks generally; this is the Messenger-specific slice.)

**Permissions and access** (R3). Page access token must be requested from a person who can perform the
**`MODERATE`** task on the Page. Permissions: **`pages_messaging`** and **`pages_manage_metadata`**. With
Standard Access the app receives notifications **only from people with a role on the app**; **Advanced
Access**, which requires App Review, is needed to receive notifications from customers. The app must be
published before you start. This is the mechanism behind the error-200 family in §3.

---

## 3. Error codes and failures

All rows are from R2 ("Common Error Codes") unless marked R7. **Quotes ending in `…` were truncated at 125
characters by the fetch tool and are incomplete.** Where R2 lists no cause, the cell says `not stated`.

### 3.1 Outside the allowed window

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 10 | 2534022 | "This message is sent outside of allowed window." | Outside the 24-hour window after the customer's last message. Messages can only be sent within that window. | Wait for an inbound message, or send with a valid tag (`HUMAN_AGENT` for a human reply). | Nothing — no message arrives. | R2 |
| 10 | 2018278 | "This message is sent outside of allowed window." | Outside the messaging window "under a newer policy". | `not stated` — R2 lists no solution. | Nothing. | R2 |
| 10 | 2018065 | "…You need News Messaging permission to be able to do it." | Outside the window; News Messaging permission is required. | Only News Page Index Pages qualify; see `NON_PROMOTIONAL_SUBSCRIPTION` (§2.6). | Nothing. | R2 |

Two distinct subcodes carry the **identical** message string. Lynomia must classify on `code/subcode`, never
on the message text, and must not collapse `2534022` and `2018278` into one article without saying they
differ — R2 distinguishes them only as "the 24-hour window" versus "a newer policy", and does not say what
that newer policy is (§6.2).

### 3.2 User cannot be messaged / has blocked the Page

| Code | Subcode | Title as Meta words it | What it means | What the business can do | Source |
|---|---|---|---|---|---|
| 551 | — | "User Block Error: This person isn't receiving messages from you right now." | Recipient isn't currently receiving messages from the Page, "which can indicate a block". | Nothing recoverable. Stop retrying this recipient. | R2 |
| 551 | 1545041 | "This person isn't available right now." | Recipient is currently unavailable. | Do not retry immediately. | R2 |
| 551 | — | "This person isn't available right now." | Same code, **different message text** than R2's 551. | — | **R7** |
| 200 | 1545041 | "Message Not Sent: This person isn't available right now." | Recipient is currently unavailable. | Do not retry immediately. | R2 |
| 10 | 2018108 | "They can't receive your messages right now." | Recipient currently can't receive messages. | `not stated` — R2 lists no solution. | R2 |
| 2 | — | "An unexpected error has occurred. Please retry your request later." | Transient platform error — **but R2 also states it "can also occur if the customer blocked the business."** | Check Meta's developer platform status before assuming a block. | R2 |
| 9000001 | — | "This Message has been deleted by the user or the business." | The message was deleted. R2 lists `OAuthException` as the solution. | — | R2 |
| 10903 | — | "This user cant reply to this activity" | `not stated` (verbatim, including the missing apostrophe). | — | **R7** |
| 10904 | — | "The page has messages disabled in the settings" | Messaging is turned off for the Page. | Page admin must re-enable messaging. | **R7** |

Four codes (`551`, `551/1545041`, `200/1545041`, `10/2018108`) all mean roughly "this person is not
receiving your message", and Meta's own text distinguishes *blocked* from *unavailable* only loosely. **Meta
does not state how a business can tell a block from a temporary unavailability** (§6.2). An honest Lynomia
article says so rather than guessing, and `code 2` is the trap: it reads as transient but R2 says it can mean
a block.

### 3.3 Policy violations and restrictions

| Code | Subcode | Title as Meta words it | What it means | Source |
|---|---|---|---|---|
| 10 | 1893063 | "You are temporarily restricted from sending messages." | Page temporarily restricted for activity that violates Messaging Policies. | R2 |
| 613 | 2018338 | "Warning! You are engaging in behavior that may be considered bothersome or abusive by users." | **Message tags are sent too often.** Slow down, or messaging restrictions may apply. | R2 |
| 2022 | — | "The ability to send commerce messages has been temporarily disabled." | Feature limited after a policy violation. R7 words it "…for this application". | R2, R7 |
| 368 | — | "The action attempted has been deemed abusive or is otherwise disallowed" | `not stated`. | **R7** |
| 10 | 1404170 | "Application does not have permission for this action" | Page temporarily restricted from sending Marketing Message opt-in requests. | R2 |
| 10 | 1893015 | "(#10) This user has currently stopped notification messages for this topic" | Page sent a Marketing Message after the user chose to stop these messages. | R2 |
| 100 | 2534029 | "The business has been blocked from sending messages via the IG Messaging API" | Instagram only. Policy violations must be fixed first. | R2 |

`613 / 2018338` is the enforcement edge of the tag rules in §2.6 and is the code a Lynomia customer will hit
if they use `HUMAN_AGENT` as a general-purpose bypass. R6's escalation path for a restricted Page: an
explanation is emailed to the **Page Support Inbox**, questions can be answered by replying to that email,
and "Expect a response within 3 business days."

### 3.4 Permissions, access and tokens

| Code | Subcode | Title as Meta words it | What it means | Source |
|---|---|---|---|---|
| 190 | — | "Access Token Error: Invalid OAuth access token." (R7: "Invalid OAuth 2.0 Access Token") | Access token invalid. | R2, R7 |
| 200 | — | "Permission Error: Cannot message users who are not admins, developers or testers of the app…" | App isn't live and the `pages_messaging` permission hasn't been reviewed. | R2 |
| 200 | 2018028 | "Cannot message users who are not admins, developers or testers of the app…pages_messaging…" | Blocked until `pages_messaging` is reviewed **and** the app is live. | R2 |
| 200 | 2018027 | "Cannot message users who are not admins, developers or testers of the app…pages_messaging_phone_number…" | Blocked until `pages_messaging_phone_number` is reviewed and the app is live. | R2 |
| 200 | 2018021 | "Requires phone matching access fee to be paid by this page…" | A fee is required unless the recipient is an app admin, developer or tester. | R2 |
| 200 | — | "Permissions error" | `not stated`. | **R7** |
| 200 | 2534041 | "The account owner has disabled access to instagram direct messages." | The IG Professional account owner revoked the app's access. | R2 |
| 1 | 1–99 | "An unknown error occurred." | Often missing permissions; the app may need **Advanced Access, Business Verification, or specific permissions**. | R2 |
| 2018247 | — | "Insufficient permission to access user profile." | App lacks permission for one or more requested profile fields. | R2 |
| 2018218 | — | "No profile available for this user." | User Profile API doesn't support phone-number-created Messenger accounts. | R2 |

The error-200 family is the single most likely first-run failure for a new Lynomia Messenger connection: it is
not a bug, it is Standard Access plus an unpublished or unreviewed app (R3, §2.8). `code 1 / subcode 1–99` is
worth an article of its own precisely because "An unknown error occurred" usually is not unknown — R2 says it
is usually permissions.

### 3.5 Rate limits and pacing

| Code | Subcode | Title as Meta words it | What it means | Source |
|---|---|---|---|---|
| 4 | — | "Rate Limit error: Application request limit reached." / "Too many send requests to phone numbers" | Rate limit reached. Pause requests until volume drops below the limit. | R2 |
| 613 | 2534040 | "Calls to this api have exceeded the rate limit." | App hit the rate limit. Pause and retry later. | R2, R7 |
| 4 | 2018354 | "There has to be a minimum delay between 2 notifications for the given notification" | Marketing Message sent before the `notification_messages_frequency` interval. R2 notes this is **not** an abuse flag; track recipients and exclude them from the next batch. | R2 |
| 9 | 2018352 | "User is performing too many actions" | Marketing Message opt-in request limit exceeded. | R2 |
| 2018144 | — | "…only 5 notifications can be sent to a user within 10 days since they last played." | Instant Game notification limit. | R2 |

### 3.6 Thread control and handover failures

These are the codes that only appear once two systems compete for a thread — exactly Lynomia's situation.

| Code | Subcode | Title as Meta words it | What it means | Source |
|---|---|---|---|---|
| 2018300 | — | "Message failed to send because another app is controlling this thread now." | **Another app currently owns the thread.** | R2 |
| 2018321 | — | "The chat is currently controlled by Messenger while the user is in an automated question and answer flow." | Messenger controls the chat during an automated flow. Wait for it to finish. | R2 |
| 2018171 | — | "Only available to Primary and Secondary Receivers." | Feature restricted to primary and secondary receivers. | R2 |
| 2018234 | — | "Denying visibility of any secondary receiver to another secondary receiver other than itself." | Visibility restriction between secondary receivers. R2 lists no description. | R2 |
| 10 | 2018336 | "User Thread Impact" | Check with the User Level Menu API; this subcode means the thread is impacted. | R2 |

`2018300` and `2018321` are the two an agent will actually see: a send fails because a bot or Messenger's own
automated flow holds the thread. Note that `2018171` and `2018234` still speak of Primary and Secondary
Receivers — more evidence that the roles are not fully gone, against R4's claim (§6.3, C2).

### 3.7 Attachments and media

| Code | Subcode | Title as Meta words it | What it means | Source |
|---|---|---|---|---|
| 100 | 2018008 | "Failed to fetch the file from the url." | URL invalid, no valid SSL certificate, bad file size, or server too slow. | R2 |
| 100 | 2018047 | "Upload attachment failure." | Often a media type that doesn't match the file at the URL. | R2 |
| 100 | 2018074 | "Possible invalid ID or you do not own the attachment." | Invalid ID or no ownership. See the Attachment Upload API. | R2 |
| 100 | 2018109 | "Attachment size exceeds allowable limit" | Attachment too large. **The limit itself is not stated on any page I retrieved.** | R2 |
| 100 | 2018294 | "Video upload timed out or video is corrupted." | Video wasn't fetched within **75 seconds**, or the file is corrupt. | R2 |

### 3.8 Parameters, IDs and payload shape

| Code | Subcode | Title as Meta words it | What it means | Source |
|---|---|---|---|---|
| 100 | — | "Bad Parameter Error: Invalid FBID." / "notification_messages_token is invalid" / "…has expired" | ID or token invalid or expired. | R2 |
| 100 | — | "Invalid parameter" | `not stated`. | **R7** |
| 100 | 33 | "Unsupported get request. Object with ID * does not exist, cannot be loaded due to missing permissions" | Object doesn't exist, app lacks permissions, or the operation isn't supported. | R2 |
| 100 | 2018001 | "No matching user found" | No matching user for the given ID. | R2 |
| 100 | 2018014 | "Cannot send both message and state at the same time." | Message and state sent in one request. | R2 |
| 100 | 2018164 | "Incorrect App ID." | App ID is wrong. | R2 |
| 100 | 2018320 | "Invalid product id" | Product ID invalid or app lacks access. | R2 |
| 100 | 2018328 | "Product template is not supported below version 8." | Product templates require API **version 8 or higher**. | R2 |
| 1 | 1–1357046 | "Received invalid JSON reply." | A batch send may succeed while the endpoint still reports an error, with a delay in error reporting. | R2 |
| 2 | 2018344 | "Privacy ToS not accepted – To use the inbox label API, you need to accept the privacy ToS." | Page admin must accept the Privacy Terms for Custom Labels. | R2 |
| 100 | — | **code 100 for deprecated tags** — "deprecated message tags are no longer allowed in API Requests." | Request used `CONFIRMED_EVENT_UPDATE`, `ACCOUNT_UPDATE` or `POST_PURCHASE_UPDATE`. Effective 2026-04-27. | **R4** |
| 10900 | — | "Activity already replied to" | `not stated`. | **R7** |
| 613 | 1893016 | "Scope of service exceeded: You may not send multiple opt–in requests with the same topic to a user." | Page sent more than one opt-in request on the same topic. | R2 |
| 10 | — | "No Permission For Pages Associated to Instant Games." | User Profile API unavailable for PSIDs tied to Instant Game Pages. | R2 |
| 10 | 2534077 | "Cannot verify the connection between the IG account, the logged in user and the page…" | Page and IG account aren't linked, or 2FA isn't enabled. Relink. | R2 |
| 10303 | — | "Account Linking Error: Invalid account_linking_token." | Account linking token invalid. | R2 |

### 3.9 Instagram-specific codes on the Messenger error page

R2 is a shared page and carries Instagram Messaging codes. Listed here for completeness and handoff to
Agents 023/024, not analysed: `100/2534013` "The page is not linked to an Instagram account";
`100/2534014` "No matching Instagram user" (requires an Instagram-scoped ID; IG User IDs not supported);
`100/2534015` "Invalid message data"; `100/2534025` "The comment is invalid for a private reply";
`100/2534037` "The action is invalid since it's not the thread owner."; `36103` "This IG account is not
eligible for API yet".

### 3.10 Out-of-scope families present on R2

R2 also documents families that do not bear on a Messenger inbox. Recorded so no later agent believes they
were missed: **Messenger Extensions / SDK** (`2018154`, `2018163`, `2018166`, `2071010`, `2071011`,
`2071014`–`2071025`), **payments** (`24001` "User canceled payment flow", `24002` "Payment request cannot be
processed due to missing privacy url", `24005` "Failed to get user ID"), and **calling** (`2018389`–`2018396`,
plus a row whose code R2 itself prints as **`TBD`** for "Call rate limit exceeded" — a genuine hole in Meta's
own table, not an omission of mine).

---

## 4. Limits and numbers

Every number below is stated by the cited source. Nothing is inferred.

| Limit | Value | Source |
|---|---|---|
| Standard messaging window | **24 hours** from the person's message / plug-in conversation start | R1, R6 |
| Human Agent tag window | **7 days** | R1, R6, R4 |
| Quick replies per message | maximum **13** | R8 |
| Quick reply `title` | **20** character limit | R8 |
| Quick reply `payload` | **1000** character limit | R8 |
| Quick reply `image_url` minimum | **24px x 24px** | R8 |
| Generic template `elements` | maximum **10** | R9 |
| Generic template element `title` | **80** character limit | R9 |
| Generic template element `subtitle` | **80** character limit | R9 |
| Buttons per generic template element | maximum **3** | R9 |
| Webhook response deadline | **200 OK within 5 seconds** | R3 |
| Webhook failure before "Webhooks Disabled" alert | delivery failing for **1 hour** | R3 |
| Video fetch deadline (send by URL) | **75 seconds** | R2 (`100/2018294`) |
| Instant Game notifications | **5** per user within **10 days** since last played | R2 (`2018144`) |
| Bot responsiveness requirement | reply within **30 seconds** | R6 |
| Grace period before send limits for responsiveness violation | **7 days** | R6 |
| Policy-restriction email response time | **3 business days** | R6 |
| Click to Messenger Ads custom thread control window | **24 hours** from last user message, extendable up to **30 days** | R4 |
| Product templates minimum API version | **version 8** | R2 (`100/2018328`) |
| Text message character limit | **not stated** on any page retrieved | R1 |
| Attachment maximum size | **not stated** on any page retrieved — the limit exists (`100/2018109`) but the number is unknown | R2, §6.1 |

---

## 5. Version and deprecation notes

| Item | Version / date | Source |
|---|---|---|
| Page Messages reference read | **v26.0** | R7 |
| Latest version listed in the changelog | **v26.0** | R4 |
| Generic template examples call | **v25.0** | R9 |
| `reply_to` and sticker fields | "Graph API v11.0+" (2021-06-08 entry), "v12.0+" (2021-09-14 entry) | R4 |
| Product templates | require API version **8** or higher | R2 |
| `CONFIRMED_EVENT_UPDATE`, `ACCOUNT_UPDATE`, `POST_PURCHASE_UPDATE` | deprecated; error **100** effective **2026-04-27** (announced 2026-03-27). Migrate to Utility Templates or the Marketing Messages API. | R4 |
| Private replies no longer require the Human Agent tag | 2021-08-06; such calls stopped working after **2021-09-13** | R4 |
| Handover Protocol revision | announced 2021-09-14, implement by **2022-03-01**; Pages migrated 2022-03-14, complete by **2022-03-18** | R4 |
| **Handover Protocol removed for Instagram** | **2025-10-23** — "Meta no longer supports the Handover Protocol for Instagram"; moved to Conversation Routing | R4 |
| Conversation Routing original coupled takeover config | deprecated **2024-06-11** | R4 |
| `is_owner` in Conversations API | **2025-10-13**; returned only when Conversation Routing is enabled | R4 |

Recent Send API and webhook additions relevant to an inbox (all R4, observational): multiple images in one
Messenger send (2025-03-19); reply to a specific past message (2025-07-15); `reply_to` object with `mid`,
`text`, `is_self_reply` on the Conversations API and Message/Echo webhooks (2025-10-06); react / edit reaction
/ remove reaction via Send API (2025-12-02); `flow_id` on `messaging_referrals` (2025-02-24);
`appointment_booking` attachment (2026-03-03); post and reel share metadata with types `post`, `ig_post`,
`reel`, `ig_reel` (2026-03-26). Instagram-side: `message_edit` subscription (2025-09-10), typing and
mark_seen sender actions (2025-09-23).

**Version-dependence of the tag enum is the live risk.** R7 is pinned to v26.0 and still lists the three
deprecated tags. Lynomia must not treat "present in the v26.0 enum" as "safe to send".

---

## 6. Ambiguities and gaps

### 6.1 Pages in scope that could not be retrieved

These four URLs return only site navigation and footer (client-side rendered) or 404. **No claim in this
report rests on them.** They must be read before the Messenger section is considered complete, and they are
where several `not stated` cells above would be filled.

| URL attempted | Result | What is missing because of it |
|---|---|---|
| `/docs/messenger-platform/reference/send-api/` and `/documentation/business-messaging/messenger-platform/reference/send-api` | navigation only | The Send API reference proper: authoritative `messaging_type` and `tag` descriptions, per-field limits, attachment types |
| `/docs/messenger-platform/send-messages/message-tags/` (and with `?locale=en_US`, and the `/documentation/...` path) | navigation only | **Per-tag descriptions and allowed/disallowed use cases for every tag**, and the authoritative Human Agent permission requirement |
| `/docs/messenger-platform/reference/attachment-upload-api/` | navigation only | Supported attachment types, **maximum file sizes**, formats, reusable attachment ID behaviour and expiry |
| `/docs/messenger-platform/handover-protocol/` (404) and `/docs/messenger-platform/reference/handover-protocol/pass-thread-control/` (redirects to the reference index) | 404 / index only | **Endpoint paths, HTTP methods and parameters for `pass_thread_control`, `take_thread_control`, `request_thread_control`** — including `target_app_id`, `metadata`, and any special value for handing a thread to the Page Inbox |

R11 points to a machine-readable documentation index at
`https://developers.facebook.com/documentation/business-messaging/messenger-platform/reference/llms.txt`,
which is the likely route to the correct current URLs. I did not fetch it (budget). **Recommended as the first
action of whoever continues this.**

### 6.2 Questions Meta's documentation does not answer

1. **`messaging_type: UTILITY` is undocumented.** It is in R7's v26.0 enum. No page I read says what it is,
   when to use it, or whether it relates to the "Utility Templates" that R4 names as the migration target for
   the deprecated tags. The connection is plausible and I am **not** asserting it.
2. **The Human Agent permission requirement rests on a changelog entry alone** (R4, 2021-06-02). No normative
   page I retrieved states that an app must apply for it. This is the gating requirement for a human inbox and
   must be confirmed before publication.
3. **Per-tag use cases are unavailable** for `CUSTOMER_FEEDBACK`, and for the three deprecated tags. §6.1.
4. **The maximum attachment size is unknown.** §6.1. Do not publish a number.
5. **No text message character limit is stated** anywhere I read.
6. **Thread-control endpoint signatures are unknown.** §6.1. Lynomia cannot document how an agent takes over a
   thread from this report alone.
7. **Blocked vs unavailable is not distinguishable** from Meta's text. `551`, `551/1545041`, `200/1545041`,
   `10/2018108` and even `code 2` overlap, and R2 hedges with "can indicate a block".
8. **Window reset semantics.** Whether every inbound message restarts the 24 hours, and what happens exactly
   at the boundary, is not stated.
9. **`10/2534022` vs `10/2018278`.** R2 distinguishes them as "the 24-hour window" versus "a newer policy" but
   never names the newer policy or says which fires when.
10. **Exclusive mode and Idle mode are named but never defined** (R4). Idle mode's only substantive appearance
    is R10's "`previous_owner_app_id` may be null in idle mode".
11. **Whether handover protocol or Conversation Routing is the correct mechanism for Messenger today.** R4
    removed handover for *Instagram* (2025-10-23) and has been building Conversation Routing since 2023, but
    no page I read says handover is deprecated for Messenger. Both appear live for Messenger. Unresolved.
12. **`message_reactions`, `messaging_handovers`, `standby`, `messaging_policy_enforcement`,
    `messaging_referrals`, `response_feedback` and `messenger_template_status_update` have no stated
    platform applicability** in R3 ("not specified"). Do not assume Messenger-only or both.
13. **The complete button type enum for templates** is not on R9.
14. **R2 prints a literal `TBD` as an error code** for "Call rate limit exceeded".

### 6.3 Contradictions requiring arbitration

| # | Contradiction | Sources | Severity |
|---|---|---|---|
| **C1** | R7 (normative, v26.0) lists `ACCOUNT_UPDATE`, `CONFIRMED_EVENT_UPDATE` and `POST_PURCHASE_UPDATE` in the `tag` enum with **no deprecation marker**, while R4 (observational) says they return error 100 from 2026-04-27 — **five and a half months before the date checked**. Either R7 is stale or the deprecation slipped. | R7 vs R4 | **blocker for publication** |
| **C2** | R10 (normative) documents `app_roles` with `primary_receiver`/`secondary_receiver`, and R2 still documents `2018171` "Only available to Primary and Secondary Receivers." and `2018234` about secondary-receiver visibility — while R4 says the September 2021 revision removed "the requirement to assign primary or secondary roles for apps". | R10 + R2 vs R4 | major |
| **C3** | R3's field table calls the Messenger read-receipt field `messaging_reads` in one place; the field name is `message_reads`. | R3 internal | minor (but would silently break a subscription) |
| **C4** | R10's `app_roles` example keys roles by app ID and shows a PSID in `recipient.id`, while R10's own properties table describes an `id` field as "Your Page ID". | R10 internal | minor |
| **C5** | R7 renders its parameter section **twice with different contents** (§2.1), including two different `recipient` shapes and two different return structs. | R7 internal | major |
| **C6** | R8 says quick replies can request "location, email address, and phone number", but its `content_type` table offers only `text`, `user_phone_number`, `user_email` — **no location type**. R8 is also inconsistent about which webhook event carries the `payload` (`messaging_postbacks` in one section, Message Received in another). | R8 internal | minor |
| **C7** | Error `551`'s message text differs between R2 ("User Block Error: This person isn't receiving messages from you right now.") and R7 ("This person isn't available right now."). | R2 vs R7 | minor |

C1 and C2 are for Agent 028 (cross-Meta error-code auditor) and the refuters 088/090/091. **C1 must be
resolved before any article tells a Lynomia customer which tags they may send.**

---

## 7. What Lynomia users would ask

These are the questions this area generates for a support desk. Each is answerable from this report unless
marked.

**The window and late replies** — the highest-volume category for a human inbox.
1. "Why did my reply fail when the customer messaged us yesterday?" → §3.1, `10/2534022`. The 24-hour window
   closed.
2. "How long do we have to reply to a Messenger customer?" → 24 hours (§2.4); 7 days with the Human Agent tag
   (§2.5).
3. "Can an agent reply after 24 hours?" → Yes, with `messaging_type: MESSAGE_TAG` and `tag: HUMAN_AGENT`,
   within 7 days, if the app holds the Human Agent permission (§2.5 — permission requirement unconfirmed, §6.2).
4. "Does the customer replying again reset the clock?" → **Meta does not state this** (§6.2.8).
5. "Can we send a promotion?" → Inside 24 hours yes; outside, only via tags (non-promotional), one-time
   notifications, or sponsored messages (§2.4).

**Delivery failures that look like bugs.**
6. "The customer never got our message and there was no error the agent could see." → §3.2. Four different
   codes mean this; `code 2` can mean a block despite reading as transient.
7. "Has this customer blocked us?" → You cannot tell reliably from Meta's errors (§6.2.7). Say so.
8. "Messenger says our Page has messages disabled." → `10904` (§3.2).
9. "Our image/video attachment won't send." → §3.7. Video must be fetchable within 75 seconds; the declared
   media type must match the file; the size limit exists but **we cannot state the number** (§6.2.4).

**First-run setup.**
10. "We connected the Page but can only message our own staff." → Error 200 family: Standard Access, app not
    published, `pages_messaging` not reviewed (§3.4, §2.8).
11. "Which permissions does the Messenger connection need?" → `pages_messaging` and `pages_manage_metadata`;
    Page token from someone with the `MODERATE` task; Advanced Access via App Review to receive customer
    messages (§2.8).
12. "We get no webhooks at all." → App must be connected and subscribed to the Page, `standby` subscribed
    separately, TLS valid and not self-signed, respond 200 within 5 seconds (§2.8).
13. "Webhooks were disabled — why?" → Delivery failed for an hour (§2.8).
14. "'An unknown error occurred' — what is it?" → Usually permissions, Advanced Access or Business
    Verification (§3.4, `code 1`).

**Competing with a bot or the Page Inbox** — the questions a multi-app inbox uniquely creates.
15. "Our agent's message failed: another app is controlling this thread." → `2018300` (§3.6).
16. "Sends fail while the customer is in a Messenger automated flow." → `2018321`; wait for the flow (§3.6).
17. "Why can we see the conversation but not the button the customer tapped?" → The standby channel omits the
    postback payload (§2.7).
18. "How does an agent take over a conversation from the bot?" → **Not answerable from this report.** The
    thread-control endpoints could not be retrieved (§6.1).
19. "Our bot asked for control and nothing happened." → A `request_thread_control` may be ignored by the
    primary receiver; Meta documents no guarantee (§2.7).

**Tags and restrictions.**
20. "Our tagged messages suddenly return error 100." → The three deprecated tags (§2.6, §5) — subject to C1.
21. "We got a warning about bothersome or abusive behaviour." → `613/2018338`: tags sent too often (§3.3).
22. "Our Page is restricted from sending messages." → `10/1893063`; Meta emails the Page Support Inbox and
    replies within 3 business days (§3.3).
23. "Which tags may we use?" → **Blocked on C1.** Do not publish until resolved.

**Features.**
24. "How many quick reply buttons can we add, and how long can the labels be?" → 13; 20-character titles;
    1000-character payloads (§2.2).
25. "Are carousels/generic templates still supported?" → R9 shows no deprecation; 10 elements, 80-character
    title and subtitle, 3 buttons per element (§2.2).
26. "Does Instagram work the same way?" → No. Only `HUMAN_AGENT` is available for Instagram; read receipts use
    `messaging_seen` not `message_reads`; echoes arrive under `messages`; and **handover protocol was removed
    for Instagram on 2025-10-23** (§2.7, §2.8). Hand to Agents 023/024.

### Handoff

The code-side counterpart to this report is `docs/documentation-v2/discovery/041-facebook-messenger.md`
(Agent 041). I made no claims about Lynomia's code — I read none. Agent 000 should cross-read 041 against §2
and §3 here to find where the integration's behaviour and Meta's documented behaviour diverge, and against
§6.3 before any Messenger article is written.
