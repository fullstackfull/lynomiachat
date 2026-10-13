---
agent: 008
scope: WhatsApp conversation and pricing categories as they appear in the API — the current pricing model, the category enums, free windows, and the `pricing`/`conversation` objects in status webhooks
confidence: high
sources_normative: 14
sources_observational: 0
---

# 008 — Conversation and pricing categories in the WhatsApp API

All dates checked **2026-10-13**. Every claim below traces to a row in §1. Web search was used only to
*locate* URLs; no search-engine summary, blog, forum or community post is cited as evidence anywhere in this
report. Where a source does not state something, the cell reads `not stated` rather than a guess.

**Rates are deliberately not reproduced in this report.** §8 explains why, in terms a corpus author can act on.

## 1. Source register

Meta moved this documentation from `developers.facebook.com/docs/whatsapp/**` to
`developers.facebook.com/documentation/business-messaging/whatsapp/**`. Legacy `/docs/` URLs still resolve, but
two of them now serve **stale** content (S10, S11) — see §6.1. Any Lynomia article or code comment that links a
`/docs/whatsapp/cloud-api/webhooks/**` URL for pricing fields is pointing at the stale tree.

| # | Source URL | Page title | Product | API / version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing` | Pricing on the WhatsApp Business Platform | WhatsApp Cloud API (Pricing) | Per-message pricing effective 2025-07-01; rate cards stated effective 2026-07-01 | 2026-10-13 | normative |
| S2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/status` | Status messages webhook reference | WhatsApp Cloud API | States v23.0-and-lower vs v24.0+ behaviour | 2026-10-13 | normative |
| S3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages` | messages webhook reference | WhatsApp Cloud API | unversioned | 2026-10-13 | normative |
| S4 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog` | WhatsApp changelog | WhatsApp Cloud API / Business Management API | dated entries, 2022-02-01 → 2026-05-12 | 2026-10-13 | normative (changelog) |
| S5 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing/conversation-based-pricing` | Conversation-based pricing (Deprecated) | WhatsApp Cloud API (Pricing) | Describes the model replaced on 2025-07-01 | 2026-10-13 | normative, marked Deprecated |
| S6 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing/authentication-international-rates/` | Authentication-international rates | WhatsApp Cloud API (Pricing) | unversioned | 2026-10-13 | normative |
| S7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing/non-template-messages` | Pricing for non-template messages | WhatsApp Cloud API (Pricing) | Self-described as *upcoming* updates; dates 2026-07-01 → 2026-10-01 | 2026-10-13 | normative, but forward-dated announcement |
| S8 | `https://developers.facebook.com/docs/whatsapp/updates-to-pricing/new-template-guidelines` | Template categorization | WhatsApp Business Management API | `allow_category_change` removed 2025-04-09 | 2026-10-13 | normative |
| S9 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/marketing-messages/pricing/` | Set a max price for marketing messages (BETA) | Marketing Messages Lite API | BETA; open beta stated 2026-10-01, GA stated Q2 2027 | 2026-10-13 | normative, beta feature |
| S10 | `https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/payload-examples` | Webhooks payload examples | WhatsApp Cloud API | **stale** — still shows `"pricing_model": "CBP"` | 2026-10-13 | normative page, stale content |
| S11 | `https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components` | Components (Cloud API webhooks) | WhatsApp Cloud API | **stale** — `CBP` example, no field tables | 2026-10-13 | normative page, stale content |
| S12 | `https://developers.facebook.com/docs/whatsapp/on-premises/webhooks/components` | On-Premises API sunset | WhatsApp On-Premises API | final supported client expired 2025-10-23 | 2026-10-13 | normative (sunset notice) |
| S13 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview/` | WhatsApp webhooks | WhatsApp Cloud API | unversioned; no field-level pricing detail | 2026-10-13 | normative |
| S14 | `https://business.whatsapp.com/products/platform-pricing#rates` | WhatsApp Business Platform pricing — rates | Meta business site (rate source) | current rate cards, per currency | **not fetched** (see §8) | normative rate source, referenced by S1, deliberately not retrieved |

## 2. The rules

### 2.1 The current model is per-message, and it has been since 2025-07-01

Meta charges **per message**, not per conversation. S1 states per-message charging effective **July 1, 2025**;
the changelog entry for that date reads "Per-message pricing is now live" (S4). The predecessor model,
conversation-based pricing (CBP), is explicitly marked deprecated and "was replaced by per-message pricing on
July 1, 2025" (S1, S5).

The lineage matters because Lynomia's stored webhook history may straddle it:

| Date | Model change | Source |
|---|---|---|
| 2022-02-01 | WhatsApp switched *from* notification-based *to* conversation-based pricing | S4 |
| 2023-06-01 | New conversation-based model using the marketing/utility/authentication categories (template categories made mandatory in v16.0, 2023-02; all templates by 2023-05-01) | S4 |
| 2023-04-04 | Business-initiated conversations became ineligible for free-tier conversations | S4 |
| 2024-11-01 | "Service conversations are now free for all businesses, including via AI-enabled conversational experiences" | S4, S5 |
| **2025-07-01** | **Per-message pricing live; CBP deprecated** | S1, S4, S5 |

Meta also publishes its own change cadence: pricing updates occur "on the 1st day of each quarter," with stated
notice periods of 1 month for rate-card updates, 3 months for pricing-model add-ons and 6 months for
pricing-model changes (S1). That cadence, not any individual number, is the durable fact for a help article.

### 2.2 The categories

Two closely related but **not identical** vocabularies exist, and conflating them is the single most common
integration mistake in this area.

**Template categories** (what a business chooses when it creates a template): `MARKETING`, `UTILITY`,
`AUTHENTICATION`. S1's "Message template categories" section lists exactly these three. **`SERVICE` is not a
template category** — S8 does not mention service at all, and S1 discusses service only under "Free non-template
messages."

**Pricing categories** (what appears in a status webhook, lowercase): `authentication`,
`authentication-international`, `marketing`, `marketing_lite`, `referral_conversion`, `service`, `utility` (S2).
This is a *superset* of the template categories: it adds the service case, the free-entry-point case
(`referral_conversion`), the international authentication rate, and the Marketing Messages Lite product.

What qualifies as each, per S8 (template categorization) and S5 (the CBP-era definitions, which still describe
the intent):

| Category | Qualifies as (per Meta) | Source |
|---|---|---|
| Marketing | The most flexible category: awareness, sales, retargeting, app promotion. **Mixed-content templates** (e.g. an order update that also carries a promo) and templates whose content is unclear (e.g. a body that is only a placeholder) are classified marketing. | S8 |
| Utility | Must be **non-promotional**, and either specific to / requested by the user, or essential or critical to the user. Stated objectives: opt-in management, order management, account alerts, feedback surveys, continuing a conversation on WhatsApp. Feedback surveys must be specific to an order or interaction — generic surveys are not approved as utility. "Continuing a conversation" must not begin without the user having requested it. A separate essential/critical list covers severe weather, crisis response, health emergencies, system outages, product recalls and privacy disclosures. | S8 |
| Authentication | Only authentication templates may send one-time passcodes for identity verification. Requirements: use a Template Library authentication template, configure a one-time-password button (copy-code or one-tap), no URLs, media or emojis in content or parameters, and parameters limited to 15 characters. | S8 |
| Service | Not a template category. Describes non-template messages sent to resolve a customer inquiry inside the customer service window. | S1, S5 |
| `marketing_lite` | Marketing Messages Lite API traffic. Webhooks use lowercase `marketing_lite`; Pricing Analytics uses `MARKETING_LITE`; Template Analytics uses `product_type` `MARKETING_MESSAGES_LITE_API`. | S9 |
| `authentication-international` | An authentication template billed at the international rate (§2.5). | S2, S6 |
| `referral_conversion` | The free-entry-point case (§2.4). | S2 |

### 2.3 How the category is chosen at send time, and yes — Meta re-categorises

The category is **not** a send-time parameter. It is a property of the template, fixed at approval, and applied
when the template is used: "Whenever a template is used, a business accepts the charges associated with the
category applied to the template at time of use," and businesses are "responsible for reviewing the category
assigned to their approved templates" (S1). A non-template message is categorised `service` by virtue of being
a non-template message inside the service window.

At creation, the business selects a category, WhatsApp validates it against the content, and the template lands
`APPROVED`, `PENDING` or `REJECTED`; a wrong-category rejection carries `reason` = `INCORRECT_CATEGORY` (S8).
Since **2025-04-09**, a template submitted as `UTILITY` that WhatsApp judges to be marketing is simply
**approved as `MARKETING`**, and the `allow_category_change` property is no longer supported because that is now
the default behaviour (S8, S4).

**Meta re-categorises already-approved templates.** S8 states a recurring process began **2024-07-01** to
identify and update miscategorised templates, extended to authentication on **2024-10-01**, and that automatic
updates apply only to approved templates that did not meet the guidelines at approval. The two paths differ
sharply:

| Re-categorisation | Notice | Outcome | Source |
|---|---|---|---|
| Utility → Marketing | 1 day in advance. **From 2025-04-16, businesses previously warned for misuse get no advance notice and the change is instant.** | Template stays `APPROVED` and remains usable — it just costs the marketing rate. | S8 |
| Marketing or Utility → Authentication | Advance notice given | The category does **not** change; instead, on the first day of the following month the template status becomes `REJECTED`. | S8 |

Notification channels: email to people with full control of the WABA; a WhatsApp Manager banner plus a
downloadable CSV; the **`template_category_update` webhook** (fields `new_category`, `previous_category`,
`correct_category` — subscription field added 2023-03-17 per S4); and the message-templates endpoint, where a
`category` that disagrees with a non-empty `correct_category` means an update is pending (S8).

Appeals: review is requested through WhatsApp Manager / Business Support Home, for `UTILITY` or `MARKETING`
templates that are `REJECTED` and for `MARKETING` templates that are `APPROVED`, within **60 days** of creation
or of the category update. A utility template scheduled to become marketing can be reviewed; a marketing or
utility template scheduled for rejection cannot (S8).

Persistent misclassification escalates to enforcement: warning → utility message rate limiting (minimum 7 days)
→ utility template restriction, where **all** utility templates are recategorised to marketing (7 days; 30 for
repeat violations) → portfolio-level restriction (30 days). These arrive on the `account_update` webhook with
`violation_info.violation_type` and `restriction_info.restriction_type` / `.expiration`; stated values include
`UTILITY_TEMPLATE_ABUSE`, `RESTRICTED_UTILITY_TEMPLATES` and `RATE_LIMITED_UTILITY_TEMPLATE_MESSAGING` (S8).

### 2.4 Free messages: there is no documented monthly free quota under per-message pricing

Under per-message pricing, "free" is a function of **window state and message type**, not of a monthly
allowance. S1 states three free cases:

1. **Non-template messages** — "Non-template messages, which can only be sent within an open customer service
   window, are free." Webhook: `"type": "free_customer_service"`, `"category": "service"` (S1).
2. **Utility templates inside an open customer service window** — "Utility templates delivered within an open
   customer service window are free." Webhook: `"type": "free_customer_service"`, `"category": "utility"` (S1).
3. **Everything inside an open Free Entry Point window** — free for 72 hours (below).

**Free Entry Point (FEP) windows**, quoted from S1: if a user messages you via a Click to WhatsApp Ad or a
Facebook Page Call-to-Action button "using a device running our Android or iOS app (our desktop and web apps are
not supported)," then a 24-hour customer service window opens as normal; "If you respond within 24 hours using
any type of message, the message will be free, and a Free Entry Point ("FEP") window will be opened, starting
from the time when you responded." FEP windows "remain open for 72 hours. While open, you can send any type of
message to the user at no charge." And critically: "the customer service window is independent of the FEP
window, so if the customer service window closes, you will only be able to send template messages." In webhooks
an FEP message carries `pricing.type` = `free_entry_point`, and `category` / `origin.type` =
`referral_conversion` (S2).

**On the CBP-era free tier**: S5 states "As of November 1, 2024, you can open an unlimited number of service
conversations at no charge," and gives **no numeric limit**. S4's 2023-04-04 entry records that
business-initiated conversations stopped being free-tier eligible. **No page I read states a monthly free
message or free conversation quota under per-message pricing.** A figure of this kind circulates widely; it is
not in any source in §1, so this report does not assert one. If a Lynomia article needs it, it must be sourced
fresh from S1/S14 at writing time.

### 2.5 Authentication-international

This is a *rate variant*, not a template category a business can choose. Per S6, an authentication template
message is billed at the authentication-international rate when all three hold: the business is eligible; the
business's primary business location is in a different country from the recipient; and the message was delivered
on or after the business's start time for that country. The determination uses the **recipient's country calling
code**, and messages to users in the business's own primary-location country stay at the domestic authentication
rate.

Eligibility is reached after sending **more than 750K messages outside customer service windows in a moving
30-day period**, across all of the business's WABAs, to users in countries carrying this rate — and eligibility
is **permanent**. Start times are set **30 days** after the eligibility date, are business- and
country-specific, and are delivered by email and webhook or read from the `auth_international_rate_eligibility`
API field. The primary-business-location field has existed in Business Manager since 2024-05-01 (S6).

Markets S6 lists as carrying the rate: Egypt, India, Indonesia, Malaysia, Nigeria, Pakistan, Saudi Arabia, South
Africa, United Arab Emirates. S1 separately notes a higher authentication-international rate for India from
2026-04-01, and new authentication-international rates for listed markets from 2026-10-01 (announced by
2026-06-01, with the rates themselves to be announced by 2026-09-01).

### 2.6 What the `pricing` and `conversation` objects actually contain

This is the authoritative field reference, from S2 ("Status messages webhook reference"). Both objects are
included **only** with a `sent` status **plus** either `delivered` or `read` — and S2 states the `pricing`
object "can only appear in one or the other" of `delivered`/`read`.

`pricing` object:

| Field | Type | Values / meaning | Source |
|---|---|---|---|
| `billable` | Boolean | Whether the message is billable. **Deprecated**: "The `billable` property will be deprecated in a future versioned release." Use `type` and `category` instead. | S2 |
| `pricing_model` | String | `CBP` = conversation-based pricing, set only for webhooks sent **before 2025-07-01**; `PMP` = per-message pricing. | S2 |
| `type` | String | `regular` (billable); `free_customer_service` (a utility template or a non-template message sent within a customer service window); `free_entry_point` (sent within an open free entry point window). | S2 |
| `category` | String | `authentication`, `authentication-international`, `marketing`, `marketing_lite`, `referral_conversion`, `service`, `utility`. | S2 |

`conversation` object:

| Field | Type | Values / meaning | Source |
|---|---|---|---|
| `id` | String | **For v24.0 and higher the `conversation` object is omitted entirely**, unless the message was sent inside an open free entry point window — in which case the id is unique per FEP window. For v23.0 and lower the id is unique per message, except within FEP windows. | S2 |
| `expiration_timestamp` | String (Unix timestamp) | When the conversation expires. **Included only for the `sent` status.** | S2 |
| `origin.type` | String | `authentication`, `authentication_international`, `marketing`, `marketing_lite`, `referral_conversion`, `service`, `utility`. S2's parameter table calls this the conversation category. | S2 |

`status` values (S2): `sent`, `delivered`, `read`, `played` (first time a voice message is played), `failed`.
S3 adds that each outgoing message can produce up to three status webhooks, and that outgoing message errors
appear in the `statuses` array.

Observed `pricing` shapes on S1, in full:

- free non-template: `"billable": false`, `"pricing_model": "PMP"`, `"type": "free_customer_service"`, `"category": "service"`
- free in-window utility: `"billable": false`, `"pricing_model": "PMP"`, `"type": "free_customer_service"`, `"category": "utility"`
- billable: `"billable": true`, `"pricing_model": "PMP"`, `"type": "regular"`, `"category": "<PRICING_CATEGORY>"` — where S1 says "The `<PRICING_CATEGORY>` tells you what rate was applied (for example, `marketing`)."

There is **no `cost` or amount field in a standard status webhook.** The only documented monetary field is a
`cost` object available when the Marketing Messages Lite *max price* beta is enabled, on `delivered` and `read`
events, with `amount` (Float, in the currency's base unit) and `currency` (String) — and S9 says plainly that
the webhook price may differ from the invoice "due to small variations in data processing (same as Analytics
API)" and that "Your billing invoice is the source of truth for final pricing."

## 3. Error codes and failures

This area produces almost no numeric Graph error codes. It produces **status-field values and webhook
notifications** instead. Request-time send-failure codes are agent 005's scope and are not duplicated here;
nothing in the pages I read ties a numeric code specifically to pricing or category.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| not stated | not stated | `INCORRECT_CATEGORY` (template `reason`) | The submitted template's content does not match the category chosen | Resubmit under the correct category, or request review within 60 days | nothing (template never sent) | S8 |
| not stated | not stated | `template_category_update` webhook | Meta changed, or is about to change, an approved template's category; carries `previous_category`, `new_category`, `correct_category` | Accept the new rate, or request review where eligible | nothing | S8, S4 |
| not stated | not stated | `UTILITY_TEMPLATE_ABUSE` (`violation_info.violation_type`) | The WABA is being enforced against for labelling marketing templates as utility | Correct categorisation; appeal per template via Business Support | nothing directly | S8 |
| not stated | not stated | `RATE_LIMITED_UTILITY_TEMPLATE_MESSAGING` (`restriction_info.restriction_type`) | Utility message sending is rate-limited, minimum 7 days | Wait out `restriction_info.expiration`; fix categorisation | utility messages arrive late or not at all | S8 |
| not stated | not stated | `RESTRICTED_UTILITY_TEMPLATES` (`restriction_info.restriction_type`) | **All** utility templates are recategorised to marketing for 7 days (30 for repeat violations) | Wait out the restriction; fix categorisation | messages still arrive, but every utility send is billed as marketing | S8 |
| not stated | not stated | status `REJECTED` following a marketing/utility → authentication notice | On the first day of the following month the template is rejected rather than recategorised | Build a proper authentication template from the Template Library | the template stops sending | S8 |

## 4. Limits and numbers

Only numbers a source states. Nothing inferred, nothing remembered.

| Number | What it governs | Source |
|---|---|---|
| 24 hours | Customer service window length | S1 |
| 72 hours | Free Entry Point window length | S1, S5 |
| more than 750K messages / moving 30-day period | Authentication-international eligibility threshold (messages outside customer service windows, across all WABAs, to rate-carrying countries) | S6 |
| 30 days | Gap between authentication-international eligibility date and the per-country start time | S6 |
| 60 days | Window to request review of a template category decision, from creation or from the update date | S8 |
| 1 day | Standard advance notice for a utility → marketing recategorisation (removed for warned businesses from 2025-04-16) | S8 |
| 7 days / 30 days | Minimum utility rate-limiting duration; utility-template restriction duration (30 for repeat violations); portfolio-level restriction duration | S8 |
| 15 characters | Maximum authentication template parameter length | S8 |
| up to 3 | Status webhooks per outgoing message (`sent`, `delivered`, `read`) | S3 |
| 1 month / 3 months / 6 months | Notice periods for rate-card updates / pricing-model add-ons / pricing-model changes | S1 |
| 1st day of each quarter | The only dates on which pricing updates take effect | S1 |
| $2.00 USD per 1M tokens | Meta Business Agent messages, single global rate, charging stated effective 2026-08-01 | S7 |

Deliberately absent: every per-country, per-category message rate. See §8.

## 5. Version and deprecation notes

| Version / date | Note | Source |
|---|---|---|
| **v24.0 and higher** | The `conversation` object is **omitted entirely** from status webhooks, unless the message was sent in an open FEP window. The changelog entry (2025-10-08) says status webhooks for v24.0+ "no longer includes the conversation object," except during an open Free Entry Point window. | S2, S4 |
| v23.0 and lower | `conversation.id` is unique per message (not per conversation), except within FEP windows | S2 |
| future versioned release | `pricing.billable` will be deprecated; use `pricing.type` and `pricing.category` | S2 |
| 2025-07-01 | CBP replaced by PMP. `pricing_model` = `CBP` is set only for webhooks sent before this date. S1 records one edge case: messages in utility conversations opened before the switch carry `pricing_model` `CBP` and have the utility conversation id assigned to `conversation.id`. | S1, S2, S5 |
| 2025-04-09 | `allow_category_change` no longer supported at template creation; utility→marketing approval is the default | S8, S4 |
| 2025-10-23 | On-Premises API: final supported client version expired. The On-Premises webhook components page — historically the only place with full `pricing`/`conversation` field tables — now serves a sunset notice. | S12 |
| v16.0 (2023-02) | First version requiring a template category; all templates by 2023-05-01 | S4 |
| 2026-05-13 | Meta no longer charges "AI Providers" for non-template messages delivered to users in EU/EEA markets; Brazil charges remain in effect | S4 |
| BETA (open beta stated 2026-10-01, GA Q2 2027) | Max price for marketing messages, and with it the `cost` object on `delivered`/`read` | S9 |

## 6. Ambiguities and gaps

Recorded, not resolved.

### 6.1 Two Meta pages disagree about whether service messages are billable today — and today is past the date

S7 ("Pricing for non-template messages") states, under "Effective October 1, 2026," that charging **begins** for
service messages (per message, at utility/authentication rates by market, no volume tiers) and for utility
messages sent inside an open 24-hour customer service window. Today is **2026-10-13**, twelve days after that
date. But S1, the current pricing page, still states that "Non-template messages, which can only be sent within
an open customer service window, are free" and "Utility templates delivered within an open customer service
window are free," with no October 2026 qualifier — S1's only October 2026 content is a rate-card update section
for specific markets. The changelog (S4) contains **no entry** announcing that service or in-window utility
charging took effect; its only 2026 pricing entry is the 2026-05-12 AI-Providers/EU-EEA change. S7 also
describes the `pricing` object for charged service messages as `"type": "regular"`, `"category": "service"`,
which directly conflicts with S1's `free_customer_service`.

**This is unresolved and must not be resolved by guessing.** Either S7's date slipped, or S1 and the changelog
are lagging. A Lynomia article asserting that service messages are free — or that they are charged — would be
wrong under one of the two readings. The orchestrator should treat "is a service message billable" as an open
question to be re-checked against S1 and S4 immediately before any article on message cost is published, and
any such article should be written so the answer lives in one clearly-marked, re-checkable place.

### 6.2 `authentication-international` vs `authentication_international` — hyphen or underscore?

S2 lists `pricing.category` values including the **hyphenated** `authentication-international`, and explicitly
notes that this "differs from the underscored `authentication_international` used in `conversation.origin.type`."
S6, the authentication-international rates page, states that the value appearing "in the `pricing` object of
status messages webhooks" is the **underscored** `authentication_international`. One of these is wrong. A
consumer that string-matches on either spelling alone will silently misclassify international authentication
traffic. Any Lynomia code or article in this area should accept both spellings and should not present one as
canonical until Meta's pages agree.

### 6.3 `pricing_model` is never defined, only enumerated

S1 does not define the `pricing_model` field at all; S2 gives its two values and their expansion but no
semantics beyond that. There is no documented statement of what a consumer should do on encountering an
unrecognised future value.

### 6.4 The stale `/docs/` pages

S10 and S11 are live, linkable Meta pages that still present `"pricing_model": "CBP"` and `"category":
"service"` as the example status payload, and S11 contains no field tables at all. S11 is the page most
third-party integration guides cite. Anyone reading only those pages in 2026 would conclude conversation-based
pricing is current. Lynomia documentation must link S1 and S2, never S10 or S11.

### 6.5 Not stated anywhere I read

- Whether, under per-message pricing, any monthly free message or free conversation allowance exists (§2.4).
- What `pricing.category` a Meta Business Agent message carries — S7 says analytics and webhook details "are
  forthcoming."
- What `type`/`category` an in-window utility message will carry if and when S7's charging takes effect.
- How `played` status interacts with the pricing object, given S2's rule that `pricing` appears with `sent` plus
  one of `delivered`/`read`.
- Whether a re-categorisation applies to messages already queued or in flight.
- Whether `conversation.expiration_timestamp` refers to the customer service window, the FEP window, or a
  billing conversation, in a v24.0+ world where the object only appears for FEP.

## 7. What Lynomia users would ask

1. "Why was I charged for this message when the customer messaged me first?" — the service window had closed, or
   the reply was a non-utility template.
2. "Why did my utility template suddenly cost marketing rates?" — a utility → marketing recategorisation, which
   may have arrived with one day's notice or none (§2.3).
3. "Why did this template stop working?" — a marketing/utility → authentication notice ends in `REJECTED` on the
   1st of the following month, not in a category change.
4. "Where do I see what a message cost?" — not in the status webhook; §8.
5. "What is `referral_conversion`?" — the free-entry-point category; the business almost certainly does not
   recognise the term from any UI.
6. "The webhook stopped sending me a conversation id." — expected on v24.0+ (§5).
7. "Why are my OTP messages more expensive this month?" — authentication-international eligibility is permanent
   once crossed (§2.5).
8. "Why are all my utility templates billing as marketing?" — `RESTRICTED_UTILITY_TEMPLATES` enforcement.
9. "Is a service reply free?" — the honest current answer is §6.1: Meta's own pages disagree.
10. "Can I choose the category when I send?" — no; it is fixed on the template at approval.

## 8. What an operator can and cannot know about why a message cost what it cost

**What the API tells you.** A status webhook answers exactly two cost questions: *was this billable*
(`pricing.type` — `regular` vs `free_customer_service` vs `free_entry_point`) and *which rate class applied*
(`pricing.category`). That is the whole of it. `pricing.category` is the single most useful cost field in the
platform, and S1 says so in as many words: "The `<PRICING_CATEGORY>` tells you what rate was applied."

**What the API does not tell you.**

- **No amount.** There is no price, no currency and no cost field in a standard status webhook (S2). The only
  monetary field anywhere is the `cost` object behind the max-price beta, and even that is an *estimate* that
  "may differ from your invoice," with S9 stating that "Your billing invoice is the source of truth for final
  pricing."
- **No volume tier.** S1 states plainly that "tiering information is not included in any webhooks." Two
  identical marketing messages to the same country can be billed at different rates depending on where the
  business sits in its monthly volume, and no webhook reveals which.
- **No recipient rate.** The rate is a function of category × recipient country × currency × quarter. The
  webhook gives you the category only; the country must be derived from the recipient, and the rate must be
  joined from a rate card that lives outside the API as a CSV/PDF and an interactive table (S1, S14).
- **No provenance for the category.** `pricing.category` tells you the rate class applied; it does not tell you
  whether that class was the one the business chose or one Meta reassigned. Reconstructing that requires the
  `template_category_update` webhook history plus `category` / `correct_category` on the message-templates
  endpoint (S8). An operator looking only at status webhooks cannot distinguish "we sent marketing" from "Meta
  made our utility template marketing yesterday."
- **No conversation grouping, on current versions.** On v24.0+ the `conversation` object is gone except for FEP
  (S2, S4). Cost attribution by conversation is no longer reconstructable from webhooks; per-message is the only
  available grain, which is consistent with the billing model but breaks any pre-2025 reporting that grouped by
  `conversation.id`.
- **Partial window information.** `conversation.expiration_timestamp` appears only on the `sent` status (S2),
  and only at all when the `conversation` object is present.

**One counting hazard worth stating in any article.** S2 says the `pricing` object is included with the `sent`
status *and* with one of `delivered`/`read`. A naive accumulator that adds one billable unit per observed
`pricing` object will roughly double-count. Cost reporting must key on the message id, not on webhook arrivals.

**Why this report reproduces no rates.** Per-country, per-category rates change on the first day of each
quarter (S1), differ by billing currency, are distributed as versioned CSV and PDF rate cards plus an
interactive table on Meta's business site (S1 → S14), and are the subject of market-specific updates already
announced for 2026-04-01 and 2026-10-01 (S1). A number copied into a Markdown corpus would be stale within a
quarter while still reading as authoritative, and a support article quoting a wrong rate is worse than one that
quotes none. The durable facts are the **model** (per-message since 2025-07-01), the **category that selects the
rate**, the **quarterly change cadence with its 1/3/6-month notice periods**, and the **link** — S14, as
referenced by S1. Lynomia documentation should state the model and link the rate page, and should never mirror
the rate table. For the same reason S14 was deliberately not fetched for this report: there was nothing on it
this report is permitted to carry.
