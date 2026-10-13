---
agent: 016
scope: The WhatsApp 24-hour customer service window — what opens it, what may be sent inside and outside it, the failure code, cost, and the adjacent entry points that seed or bypass it
confidence: high
sources_normative: 11
sources_observational: 4
---

## 1. Source register

Every claim below references a row (R1–R15). Date checked for all rows: **2026-10-13**.

| Row | Source URL | Page title | Product | API / version context | Normative? |
|---|---|---|---|---|---|
| R1 | `https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-messages` | **Service messages** | WhatsApp Cloud API | No version in prose; request example calls `graph.facebook.com/v25.0/` | normative |
| R2 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | **Error codes** | WhatsApp Cloud API (+ Marketing Messages API) | Page states `error_subcode` is deprecated and **not returned in v16.0+** | normative |
| R3 | `https://developers.facebook.com/docs/whatsapp/pricing` | **Pricing on the WhatsApp Business Platform** | WhatsApp Business Platform | Per-message pricing in force since 2025-07-01 | normative |
| R4 | `https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components` | **messages webhook reference** | WhatsApp Cloud API | Example `pricing.pricing_model` still shows `"CBP"` | normative |
| R5 | `https://developers.facebook.com/docs/whatsapp/cloud-api/guides/mark-message-as-read` | **Mark messages as read** | WhatsApp Cloud API | Example v25.0; `<API_VERSION>` optional | normative |
| R6 | `https://developers.facebook.com/docs/whatsapp/cloud-api/typing-indicators/` | **Typing indicators** | WhatsApp Cloud API | Example v25.0 | normative |
| R7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog` | **WhatsApp changelog** | Cloud API / Business Management API | Dated entries 2022-02-01 → 2025-10-08 | observational (Meta's own changelog; records changes, does not state rules) |
| R8 | `https://developers.facebook.com/docs/whatsapp/on-premises/webhooks/components` | **On-Premises API sunset** (the components URL now serves the sunset notice) | WhatsApp On-Premises API | Final client version expired 2025-10-23 | normative |
| R9 | `https://developers.facebook.com/docs/marketing-api/ad-creative/messaging-ads/click-to-whatsapp/` | **Ads that Click to WhatsApp** | Marketing API | Examples v25.0 | normative |
| R10 | `https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/payload-examples` | **messages webhook reference** | WhatsApp Cloud API | — | normative |
| R11 | `https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks/` | **Webhooks** | WhatsApp Cloud API | — | normative |
| R12 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview/` | **Webhooks** (new documentation path) | WhatsApp Cloud API | — | normative |
| R13 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/messages` | — | — | Returned navigation chrome and a login prompt only; **no content read** | unusable |
| R14 | `https://developers.facebook.com/docs/whatsapp/business-management-api/changelog` | — | — | **HTTP 404** | dead |
| R15 | Search-result summaries of R8's former content and of R7, via site-restricted search on `developers.facebook.com` | — | On-Premises API / changelog | — | **observational, unconfirmed** — not read directly |

Two structural notes for the orchestrator. First, Meta is mid-migration from `/docs/whatsapp/**` to `/documentation/business-messaging/whatsapp/**`; both paths serve live content and the old one still resolves (R1–R6, R10, R11 vs. R7, R12). Second, R14 shows a changelog URL in Meta's own older link graph is now a 404 — any citation Lynomia stores must be re-checked, not assumed stable.

## 2. The rules

**What opens the window, and from which event exactly.** R1 states it in two sentences, quoted verbatim: *"When a WhatsApp user messages you or calls you, a 24-hour timer called a customer service window starts."* and *"If the user messages or calls you again before the timer expires, the timer resets to 24 hours."*

Three things follow that most third-party write-ups get wrong. The trigger is **the user's inbound message or the user's inbound call** — since the WhatsApp Business Calling API shipped (R7, 2025-07-15), a call is a window-opening event, and Meta's current prose puts messages and calls on exactly equal footing. The verb Meta uses for a repeat event is **"resets to 24 hours"**, not "extends": the clock is replaced, not added to. And Meta names the thing **"customer service window"**; "24-hour window" is not Meta's term of art, though the duration is right.

Meta does not say the window is keyed to a conversation record, a thread, a ticket or an agent. It is keyed to the **WhatsApp user ↔ business phone number** pair implied by the inbound event. Any product that scopes the window to its own conversation object is making a modelling choice, not quoting Meta.

**How long it lasts.** 24 hours from the triggering event (R1). No source read states any mechanism to extend, shorten, pause or disable it, and none states an endpoint that reports the window's state or remaining time. See §6.

**What may be sent inside it.** R1: *"While the window is open, you can send any of the service message types listed below to the user."* The list, introduced by *"You can send the following types of service messages during an open customer service window"*, is: Address, Audio, Contacts, Document, Image, Interactive CTA URL button, Interactive voice call, Interactive Flow, Interactive list, Interactive location request, Interactive reply buttons, Location, Sticker, Text, Video, **Reaction**. So the answer to "free-form of every type?" is: free-form of **every type Meta enumerates**, and that enumeration includes media of all kinds, interactive messages, Flows and reactions. It is a closed list, not a blanket permission — the correct phrasing is "any service message type", not "anything".

An orthogonal rule sits on top of it, and R1 states it as a reminder rather than a window rule: *"As a reminder, you can only send messages to WhatsApp users who have opted in to receiving messages from you."* An open window does not substitute for opt-in.

**What may be sent outside it.** R1: *"When the window closes, you can only send pre-approved template messages."* R1 directs outreach outside the window to **marketing, utility, or authentication** templates. No source read restricts which of those three categories may be used outside the window — all three are outbound-capable. The practical restrictions on them are per-category and live elsewhere: marketing templates carry a per-user limit (§3, code 131049) and an opt-out list (code 131050), and both are agent 017/018 territory, not window rules.

**Whether a template send inside the window is allowed, and what it costs.** Allowed: nothing in R1 or R3 forbids it, and R3 prices it, which presupposes it. Cost, from R3 — and this is the part the current Lynomia article omits entirely:

| Sent inside an open customer service window | Charged? | Source |
|---|---|---|
| Any non-template (service / free-form) message | **No** — R3: *"All non-template messages are free."* | R3 |
| Utility template | **No** — utility templates sent in an open window are free | R3 |
| Marketing template | **Yes** — marketing templates are always charged | R3 |
| Authentication template | **not stated** for the in-window case; R3 says utility and authentication are charged *outside* an open window | R3 |

R3 also states the converse constraint, which is the cost model's enforcement mechanism: *"Non-template messages can only be sent within an open customer service window."* Free-form is free **because** it is only possible while the window is open. R7 (2024-11-01) records the step that made this true: *"Service conversations are now free for all businesses, including via AI-enabled conversational experiences."*

So the single sentence a help article should carry is: inside the window you write freely and pay nothing; outside it you send a template and pay for it unless it is a utility template and the window is in fact still open.

**Reactions, read receipts, typing indicators and media — are they treated differently?** Partly, and in a direction that matters for an inbox UI.

| Capability | Window-gated? | Its own limit | Source |
|---|---|---|---|
| Reaction message | **Yes** — listed as a service message type, so open window only | — | R1 |
| Media (image, audio, video, document, sticker) | **Yes** — all are service message types | Link-hosted assets are cached by Cloud API for 10 minutes | R1 |
| Mark as read (read receipt) | **No window rule stated.** R5 does not mention the customer service window at all | R5: *"Mark incoming messages as read within 30 days of receipt."* Requires a valid `wamid` from a received message as `message_id`; invalid ID → error **131009**. Marking one message read also marks earlier messages in that conversation read | R5 |
| Typing indicator | **No window rule stated.** R6 does not mention the window | Requires the `message.id` from an inbound `messages` webhook. R6: *"The typing indicator will be dismissed once you respond, or after 25 seconds, whichever comes first."* Sent to the same `/messages` endpoint with `status: "read"` plus `typing_indicator: {"type": "text"}`. Returns `{"success": true}` | R6 |

The asymmetry is real and useful: a read receipt is governed by a **30-day** rule, not a 24-hour one, and a typing indicator is governed by having an inbound `wamid` and a **25-second** display life. Neither R5 nor R6 states that the window gates them, and neither states whether they are charged. An article that says "when the window closes nothing can be sent" is wrong about read receipts.

**The adjacent entry points.**

*Click-to-WhatsApp ads.* R9, Meta's own Marketing API page, is thinner than expected: it states only that these ads *"send people who click on your ads directly into conversations with your business in WhatsApp"*, that each clicker can be answered individually, and that the creative can carry a greeting (default: *"Hello! Can I get more info on this?"*) or an autofill message. R9 says **nothing** about the referral object, nothing about pricing, and nothing about any 24- or 72-hour window. The window and pricing consequences of a CTWA ad are documented on the pricing page, not the ads page.

*Free entry points.* R3 is the normative source and it describes a **second, separate, 72-hour window**. It opens when a user messages the business through a **Click to WhatsApp Ad** or a **Facebook Page Call-to-Action button**, on the **Android or iOS app only** — desktop and web are not supported. R3: *"If you respond within 24 hours using any type of message, the message will be free."* The 72-hour free entry point window then starts from that reply, and during it any message type is free. Critically, R3 states the customer service window runs **separately**, so the customer service window can close while the free entry point window is still open. This is the only documented path by which a business can be outside the customer service window and still send a non-template message — and Lynomia's article does not mention it at all.

*The referral object.* This is a documentation hole on Meta's side, and the honest answer is that **no page I read documents it**. R4, R10, R11 and R12 — every current Cloud API webhook page — omit it. R4 and R10 acknowledge ads only in passing (*"either directly, via an ad, or via a UI component in a previously received message"*) and their inbound examples carry only `from`, `id`, `timestamp`, `type` and `text`. R8, the page that used to carry the field list, now serves the On-Premises sunset notice instead. Per R15 (**observational, unconfirmed — search summaries, not a direct read**) the On-Premises object listed `headline`, `body`, `source_type`, `source_id`, `source_url` and optional `image`/`video` media, with `source_type` values `ad` and `post`, `source_id` being the Facebook ID of the ad or post, and an explicit warning that a referral object may contain **only** `source_url`; the same summaries say Meta's changelog notes the Cloud API referral object **differs** from the On-Premises one and that a `ctwa_clid` property was added to it. **None of that is confirmed by a page I read.** Do not publish those field names as Cloud API fact. Agent 007 (webhook payload shapes) must resolve this against a live Cloud API reference.

*The `conversation` object on status webhooks.* R4's example still shows `conversation` with `id` and `origin.type: "service"`, alongside `pricing` with `billable`, `pricing_model: "CBP"` and `category: "service"`, and R4 defines none of those fields or enumerates no other values. But R7 records a breaking change on **2025-10-08**: the status messages webhook no longer includes the `conversation` object *"unless the webhook is for a message sent during an open Free Entry Point window."* R4's own example is therefore stale relative to R7. Any Lynomia code or article that reads `conversation.origin.type` to classify a message is reading a field that is normally absent now.

## 3. Error codes and failures

| Code | Subcode | Meta's wording (verbatim, R2) | What it means | What the business can do | What the end user sees | Row |
|---|---|---|---|---|---|---|
| **131047** | none listed; `error_subcode` deprecated and not returned in v16.0+ | Details: *"More than 24 hours have passed since the recipient last replied to the sender number."* R2 gives no separate title for this code. | A free-form (non-template) send was attempted after the customer service window closed. **This is the window failure.** | R2's solution, verbatim: *"Send the recipient a template message instead."* | not stated — no message is delivered | R2 |
| **131049** | none | Details: *"This message was not delivered to maintain healthy ecosystem engagement."* | **Not a window error.** Per-user marketing template message limit. | R2: if the per-user limit is suspected, *"wait at least 24 hours before resending the template message"*; resending sooner only produces another error, as the limit may last for different periods | not stated | R2 |
| **131050** | none | Details: *"Unable to deliver the message. This recipient has chosen to stop receiving marketing messages on WhatsApp from your business."* | **Not a window error.** Recipient marketing opt-out. | Do not retry — the messages *"will not be received."* R2 also recommends subscribing to the `user_preferences` webhook to track opt-out/opt-in changes | not stated | R2 |
| **131009** | none | Invalid `message_id` on a mark-as-read call | Read-receipt failure, not a window failure | Use a valid `wamid` from a received message | n/a | R5 |
| **470** | — | **Does not appear on R2.** | Widely cited in third-party material as the 24-hour-window error; that was the **On-Premises** API code. The On-Premises API is sunset (R8). | Do not cite 470 for Cloud API | n/a | R2, R8 |

Four codes the brief asked me to check are **not** window codes: R2's entries for **131026**, **131051**, **131053** and **132000** concern non-WhatsApp numbers and outdated clients, unsupported message types, media upload failures, and template parameter-count mismatches respectively. None mentions the 24-hour window, re-engagement or opt-in.

Two things R2 does **not** give, and I will not invent: the HTTP status code returned with 131047, and any `error_subcode`, `error_data.details` string or `fbtrace_id` shape for it. R2 presents 131047 as a details string plus a solution, nothing more. If Lynomia's article quotes a longer Meta sentence for 131047 than the one above, that extra text has no source in R2.

One normative acknowledgement worth building troubleshooting copy on, from R1: *"In rare cases, you may receive a message from a WhatsApp user but be unable to respond within the customer service window."* Meta records this as a known issue, so a Lynomia article may legitimately tell an agent that an unexplained 131047 inside an apparently open window is a known Meta condition and not necessarily a Lynomia bug.

## 4. Limits and numbers

Only numbers a source states.

| Number | What it governs | Row |
|---|---|---|
| **24 hours** | The customer service window, from the user's inbound message or call; resets to 24 hours on a further inbound message or call | R1 |
| **24 hours** | Minimum wait before resending a marketing template after 131049 | R2 |
| **30 days** | Deadline to mark an incoming message as read | R5 |
| **25 seconds** | Maximum typing-indicator display, or until you respond, whichever is first | R6 |
| **10 minutes** | Cloud API internal cache for a link-hosted media asset | R1 |
| **72 hours** | The free entry point window | R3 |
| **24 hours** | The reply deadline that opens the 72-hour free entry point window | R3 |
| **up to 3** | Separate webhooks each outgoing message can produce | R4 |

No source read states a count of messages allowed inside a window, a per-window rate limit, a maximum number of window resets, or a monthly free message quota. R3 explicitly offers no monthly free quota; its free items are non-template messages and utility templates inside an open window, plus everything inside a free entry point window.

## 5. Version and deprecation notes

| Date / version | Change | Row |
|---|---|---|
| 2022-02-01 | Conversation-based pricing introduced: *"Businesses are charged per conversation, which includes all messages delivered in a 24 hour session."* The only entry describing a 24-hour **session** | R7 |
| v16.0+ | `error_subcode` deprecated and not returned in responses | R2 |
| 2024-11-01 | *"Service conversations are now free for all businesses, including via AI-enabled conversational experiences."* | R7 |
| 2025-04-08 | *"Added typing indicators so you can let WhatsApp users know that you are preparing a response."* | R7 |
| **2025-07-01** | *"Per-message pricing is now live."* R3 confirms charging is per message and that conversation-based pricing is deprecated. (R7 does not itself say per-message *replaced* CBP — that specific linkage is R3's) | R3, R7 |
| 2025-07-15 | WhatsApp Business Calling API available; 2025-08-27 and 2025-09-08 added a Call Permissions Request interactive type. Neither changelog entry mentions the messaging window — the claim that a **call** opens or resets the window comes from R1's current prose, not from the changelog | R7, R1 |
| **2025-10-08** | Status messages webhook no longer includes the `conversation` object *"unless the webhook is for a message sent during an open Free Entry Point window."* | R7 |
| 2025-10-23 | Final supported On-Premises API client version expired; On-Premises can no longer send messages to WhatsApp users | R8 |
| 2026-01-01 → 2026-10-01 | R3's billing-localization and rate-card dates (India INR, Brazil BRL from 2026-07-01, further rate updates planned 2026-10-01). Pricing *mechanics* above are unaffected | R3 |

The two entries that should change how Lynomia writes about the window are 2025-07-01 (anything in the corpus that says "conversation-based pricing" or "you are charged per 24-hour conversation" is now wrong) and 2025-10-08 (anything that reads `conversation.origin.type` is reading a usually-absent field).

## 6. Ambiguities and gaps

These are places where Meta's documentation does not answer the question. I am recording them, not resolving them.

1. **Is the window keyed to the user or to the user-plus-phone-number?** R1 says "a WhatsApp user messages you or calls you" without naming the scope. Code 131047's wording — *"since the recipient last replied to the sender number"* — implies the **sender number** is part of the key, which matters for a business with several numbers in one WABA. R1 and R2 do not reconcile this explicitly.
2. **Is there any way to read the window's state?** No source read documents an endpoint, field or webhook that reports whether a window is open or how long remains. A product must infer it from the last inbound timestamp. That is an inference, and Lynomia should describe it as such rather than as a Meta-provided value.
3. **Does a call reset the window identically to a message — and does a missed or rejected call count?** R1 treats messages and calls equally and R7's calling entries are silent on the window. Whether an unanswered inbound call starts the timer is **not stated**.
4. **Are authentication templates free inside an open window?** R3 states utility templates in an open window are free and marketing is always charged. The in-window authentication case is **not stated**.
5. **Are read receipts and typing indicators charged, and are they truly exempt from the window?** R5 and R6 are silent on both the window and on cost. Their silence is not permission; it is silence. Lynomia must not assert either direction as Meta fact.
6. **The Cloud API `referral` object is undocumented** on every current webhook page I read (R4, R10, R11, R12), and the page that documented the On-Premises version now serves a sunset notice (R8). Field names, `source_type` values and the existence of `ctwa_clid` are **unconfirmed** (R15). Hand to agent 007.
7. **What exactly a free entry point reply opens.** R3 says a reply within 24 hours is free and the 72-hour window starts from that reply. It does not state what happens if you do not reply within 24 hours, whether the 72-hour window still exists, or whether non-template sends are permitted in hours 25–72 when the customer service window has closed — R3's "any message type is free" during the window implies yes, but the permission and the price are different questions and R3 answers only the price.
8. **R4's example contradicts R7.** R4 still shows `pricing_model: "CBP"` and a `conversation` object that R7 says was removed in 2025-10-08 and R3 says is a deprecated model. Meta's own pages disagree; prefer R3 and R7.
9. **R13 and R14 are unusable** — one served a login prompt, one 404'd. Statements that would have depended on them are absent rather than guessed.

## 7. What Lynomia users would ask

"Why is the reply box greyed out on a conversation I was just in?" — because the last *inbound* event, not the last message, is older than 24 hours. "Why did my automation's message fail when a human agent could send one an hour earlier?" — 131047; the rule is time-based, not role-based. "The customer called us — can we text them now?" — per R1, yes, a call starts the window; this is new and no Lynomia article says it. "Does sending a template restart the clock so I can then write freely?" — no; only the customer's reply to it does. "What does this cost?" — free-form inside the window is free, utility in-window is free, marketing is always charged. "Our WhatsApp ad leads say the window is closed but we were told ad conversations are free" — the free entry point 72-hour window, which Lynomia documents nowhere. "Can we at least show them we've read it?" — read receipts have a 30-day rule, not a 24-hour one. "Can we get a warning before it closes?" — Meta exposes no window-state field; any countdown would be Lynomia-computed.

## 8. Assertion checklist for the existing article

Lynomia already ships `custom/db/documentation/en/whatsapp/the-whatsapp-24-hour-window.md` (and its Arabic counterpart `custom/db/documentation/ar/whatsapp/the-whatsapp-24-hour-window.md`). Below is every factual assertion an article on this subject must get right, each with the verdict my sources support, for the corpus agent (053) to check one by one. "Product claim" marks an assertion about Lynomia's own UI that is outside my read-only external scope and belongs to agent 040.

| # | Assertion as the article makes it | Verdict | Required correction / source |
|---|---|---|---|
| 1 | "When a customer messages you, you can write back freely for 24 hours." | **incomplete** | A **call** from the user also starts the timer. R1: *"When a WhatsApp user messages you or calls you, a 24-hour timer called a customer service window starts."* |
| 2 | "The clock starts at the customer's most recent message." | **incomplete** | Most recent message **or call**. R1 |
| 3 | "After that, the only thing that will send is an approved template." | **confirmed** | R1: *"When the window closes, you can only send pre-approved template messages."* |
| 4 | "It runs for 24 hours and is per conversation." | **imprecise** | 24 hours is right. "Per conversation" is Lynomia's model, not Meta's; Meta keys it to the WhatsApp user, and 131047's wording implicates the **sender number**. R1, R2 |
| 5 | "Nothing you send restarts it. Only a new message from the customer does." | **confirmed, incomplete** | Right that your own sends never reset it; add calls to the list of things that do. R1 |
| 6 | "A customer who messages at 09:00 and again at 20:00 has pushed the deadline to 20:00 the next day." | **confirmed** | R1: the timer *"resets to 24 hours."* Note Meta's verb is **resets**, not extends |
| 7 | Table: images, files, voice notes send inside the window, not outside | **confirmed** | All media types are service message types, open-window only. R1 |
| 8 | Table: an approved template sends both inside and outside the window | **confirmed** | R1 permits templates; R3 prices in-window templates, presupposing them |
| 9 | Article never states the cost of anything | **missing — high value** | R3: *"All non-template messages are free."* Utility templates in an open window are free; marketing templates are always charged; in-window authentication is **not stated** |
| 10 | "it appears in the conversation marked Failed to send, with WhatsApp's own explanation underneath" | **missing the code** | Must name **131047** and quote R2: *"More than 24 hours have passed since the recipient last replied to the sender number."* with Meta's solution *"Send the recipient a template message instead."* |
| 11 | Any claim that the window error is code **470** | **must not appear** | 470 is **not on R2**; it was the On-Premises code and On-Premises is sunset (R8) |
| 12 | "Meta caps how many unique customers you may message outside the window in a rolling 24 hours — your business messaging limit" | **conflated** | Two different Meta mechanisms: messaging limits (agent 018) and the **per-user marketing template limit** surfaced as **131049** (R2). Do not present either as a window rule |
| 13 | "it is shared by every WhatsApp number in the business portfolio" | **unverified in my scope** | No source I read supports or denies it. Route to agent 018 before publishing |
| 14 | "A WhatsApp number running through Twilio has the same 24 hours" | **observational** | No Meta page I read mentions Twilio or any BSP. The platform rule applies to the WhatsApp Business Platform, but the BSP-specific phrasing has no normative source |
| 15 | Free entry points / the 72-hour window | **absent — factual gap** | R3: a 72-hour window opens via a **Click to WhatsApp Ad** or a **Facebook Page CTA button**, **Android/iOS app only**; *"If you respond within 24 hours using any type of message, the message will be free"*; any message type is free during it; it runs **separately** from the customer service window and can outlive it |
| 16 | Click-to-WhatsApp ads as a source of in-window contacts | **absent** | R9 describes only that the ads drop people into WhatsApp conversations with a greeting; the window and pricing consequences are R3's, not R9's |
| 17 | The `referral` object on an ad-sourced inbound message | **absent, and must stay vague** | Undocumented on every current Cloud API webhook page (R4, R10, R11, R12). Do not publish field names — they are unconfirmed (R15) |
| 18 | Table implies everything is blocked when the window closes | **wrong for read receipts** | Mark-as-read is governed by **30 days** (R5), and R5 never mentions the window. Typing indicators need an inbound `wamid` and last **25 seconds** (R6). Neither page states a window rule |
| 19 | The opt-in requirement | **absent** | R1: *"you can only send messages to WhatsApp users who have opted in to receiving messages from you."* An open window is not consent |
| 20 | "There is no way to reopen it from your side" vs. the worked example's "the customer's reply to it opens a fresh 24 hours" | **reconcilable but reads as a contradiction** | Both are true — your send never resets it, the customer's reply does. Rewrite so the two sentences do not appear to conflict |
| 21 | Reactions | **absent** | A reaction is a **service message type** (R1) — it needs an open window, unlike a read receipt |
| 22 | Anything in the corpus describing charging "per 24-hour conversation" | **stale** | Per-message pricing has been live since **2025-07-01** and conversation-based pricing is deprecated (R3, R7) |
| 23 | Any Lynomia code or article reading `conversation.origin.type` | **stale** | Since **2025-10-08** the `conversation` object is absent from status webhooks *"unless the webhook is for a message sent during an open Free Entry Point window"* (R7) |
| 24 | "Lynomia Chat does not warn you that the window is about to close" | **product claim, and defensible** | Meta exposes no window-state field or endpoint in anything I read, so a countdown would have to be computed from the last inbound timestamp. Agent 040 to confirm the product side |
| 25 | "The composer is switched off", "the message is created and then fails", "a satisfaction survey is not sent", the greyed-composer string, the template button behaviour | **product claims** | Not verifiable from Meta. Agent 040 must confirm each against code |
| 26 | Troubleshooting: an unexplained failure inside an apparently open window | **absent** | R1 records a known issue: *"In rare cases, you may receive a message from a WhatsApp user but be unable to respond within the customer service window."* Worth adding to "If it does not work" |

One verification I was able to do inside the repository, so agent 053 does not repeat it: a grep across `custom/db/documentation/en/` for `470`, `conversation-based` and `origin.type` returns **no matches**, so checklist items 11, 22 and 23 are preventive — the corpus does not currently carry those stale claims. Items 1, 2, 9, 10, 15, 16, 17, 18, 19, 21 and 26 are live defects in the shipped article, and items 12, 13, 14 and 20 are live accuracy problems in it. The Arabic counterpart `custom/db/documentation/ar/whatsapp/the-whatsapp-24-hour-window.md` exists and must receive every correction the English file does.
