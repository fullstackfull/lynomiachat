---
agent: 007
scope: WhatsApp Cloud API webhook payload shapes — the `messages` webhook (every message type), the `statuses` webhook (conversation, pricing, errors), the subscribable webhook fields, and the account-level webhooks that warn a business its WABA is in trouble
confidence: high
sources_normative: 36
sources_observational: 0
---

## 1. Source register

Every source below is a page under `developers.facebook.com`, which §6.2 of the program charter designates
normative. **Date checked for every row: 2026-10-13.** **Product for every row: WhatsApp Cloud API (Meta names
the product "WhatsApp Business Platform" on these pages).**

Meta has restructured this documentation. The paths this program's older notes would use
(`developers.facebook.com/docs/whatsapp/cloud-api/webhooks/...`) now resolve to a reorganised tree under
`developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/...`. Each page is also served as
plain Markdown by appending `.md`, which is the rendition I read, so the field names in this report are Meta's
own verbatim strings rather than a paraphrase. Row 36 is Meta's machine-readable index of the whole product.

| # | Source URL | Page title | API/version context stated | Normative? |
|---|---|---|---|---|
| 1 | `/documentation/business-messaging/whatsapp/webhooks/overview` | Webhooks | none | normative |
| 2 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages` | messages webhook reference | none | normative |
| 3 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/text` | Text messages webhook reference | none | normative |
| 4 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/image` | Image messages webhook reference | none | normative |
| 5 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/audio` | Audio messages webhook reference | none | normative |
| 6 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/video` | Video messages webhook reference | none | normative |
| 7 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/document` | Document messages webhook reference | none | normative |
| 8 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/sticker` | Sticker messages webhook reference | none | normative |
| 9 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/location` | Location messages webhook reference | none | normative |
| 10 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/contacts` | Contacts messages webhook reference | none | normative |
| 11 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/interactive` | Interactive messages webhook reference | none | normative |
| 12 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/button` | Button messages webhook reference | none | normative |
| 13 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/reaction` | Reaction messages webhook reference | none | normative |
| 14 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/system` | System messages webhook reference | none | normative |
| 15 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/order` | Order messages webhook reference | none | normative |
| 16 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/unsupported` | Unsupported messages webhook reference | none | normative |
| 17 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/errors` | Errors messages webhooks reference | none | normative |
| 18 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/status` | Status messages webhook reference | **v24.0 and v23.0 behaviour both stated** | normative |
| 19 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/revoke` | Revoke messages webhook reference | none | normative |
| 20 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/edit` | Edit messages webhook reference | none | normative |
| 21 | `/documentation/business-messaging/whatsapp/webhooks/reference/messages/group` | Group messages webhook reference | none | normative |
| 22 | `/documentation/business-messaging/whatsapp/webhooks/reference/account_alerts` | account_alerts webhook reference | none | normative |
| 23 | `/documentation/business-messaging/whatsapp/webhooks/reference/account_review_update` | account_review_update webhook reference | none | normative |
| 24 | `/documentation/business-messaging/whatsapp/webhooks/reference/account_update` | account_update webhook reference | none | normative |
| 25 | `/documentation/business-messaging/whatsapp/webhooks/reference/business_capability_update` | business_capability_update webhook reference | **February 2026 field removal stated** | normative |
| 26 | `/documentation/business-messaging/whatsapp/webhooks/reference/message_template_status_update` | message_template_status_update webhook reference | none | normative |
| 27 | `/documentation/business-messaging/whatsapp/webhooks/reference/message_template_quality_update` | message_template_quality_update webhook reference | none | normative |
| 28 | `/documentation/business-messaging/whatsapp/webhooks/reference/message_template_components_update` | message_template_components_update webhook reference | none | normative |
| 29 | `/documentation/business-messaging/whatsapp/webhooks/reference/template_category_update` | template_category_update webhook reference | none | normative |
| 30 | `/documentation/business-messaging/whatsapp/webhooks/reference/phone_number_quality_update` | phone_number_quality_update webhook reference | **February 2026 field removal stated** | normative |
| 31 | `/documentation/business-messaging/whatsapp/webhooks/reference/phone_number_name_update` | phone_number_name_update webhook reference | none | normative |
| 32 | `/documentation/business-messaging/whatsapp/webhooks/reference/security` | Security webhook reference | none | normative |
| 33 | `/documentation/business-messaging/whatsapp/webhooks/reference/user_preferences` | user_preferences webhook reference | none | normative |
| 34 | `/documentation/business-messaging/whatsapp/webhooks/reference/partner_solutions` | partner_solutions webhook reference | none | normative |
| 35 | `/documentation/business-messaging/whatsapp/webhooks/reference/automatic_events` | automatic_events webhook reference | none | normative |
| 36 | `/documentation/business-messaging/whatsapp/llms.txt` | (machine-readable documentation index for the product) | none | normative |

### Not retrieved

Two pages listed in the index (row 36) returned an HTML shell rather than content on 2026-10-13 and are
therefore **not checked**: `webhooks/reference/pricing` and `webhooks/message_echoes`. Nothing in this report
depends on them. The `history`, `smb_app_state_sync` and `smb_message_echoes` reference pages were retrieved but
are summarised only at the field-purpose level (§6), because they serve WhatsApp Business app onboarding through a
solution provider, which is outside Lynomia's integration shape.

**No version header anywhere.** Only row 18 states a Graph API version context. Every other page in this set is
version-silent, so none of the field shapes below can be pinned to a Graph API version from the documentation
alone. Where behaviour is version-dependent, §5 says so.

---

## 2. The rules

### 2.1 The envelope, and the one structural split that matters

Every payload is `{ "object": ..., "entry": [ { ... "changes": [ { "value": ..., "field": ... } ] } ] }`. `object`
is `whatsapp_business_account` on every page in this set. `entry[].id` is the **WABA ID** — not the phone number
ID, and not the account ID. `changes[].field` carries the subscribed field name, which is the only reliable
discriminator for routing.

There is a split in the envelope that a single parser will get wrong:

| | `messages` field | Most account-level fields |
|---|---|---|
| `entry[].time` | **absent** from every example on rows 2–21 | **present**, Integer Unix timestamp |
| `value.messaging_product` | `"whatsapp"` | absent |
| `value.metadata` | present | absent |
| Where the timestamp lives | `value.messages[].timestamp` / `value.statuses[].timestamp`, **String** | `entry[].time`, **Integer** |

So the time of an event is a String inside `value` for message traffic and an Integer one level up for account
events. The exceptions are `user_preferences` (row 33) and `automatic_events` (row 35), which are account-level
fields that nonetheless carry `messaging_product`, `metadata` and `contacts` in the message style.

`value.metadata` has exactly two properties on every page that has it: `display_phone_number` and
`phone_number_id` (both String). `metadata.phone_number_id` is the value to route an inbound message to the right
Lynomia inbox; `entry[].id` identifies the WABA above it.

### 2.2 Incoming vs outgoing

Row 2 states the discriminator plainly: an incoming-message webhook contains a `messages` array; an
outgoing-status webhook contains a `statuses` array. Row 2 also states that status webhooks "don't describe the
contents of the outgoing message itself, only its status," and that **each outgoing message can have up to three
separate webhooks** (sent, delivered, read).

### 2.3 The `contacts` array is not guaranteed

`value.contacts[]` carries `profile.name` (String — the user's WhatsApp profile name) and `wa_id` (String), plus
`identity_key_hash` (String) which rows 3–11, 15, 16 and 21 mark "only included if identity change check
enabled".

Two normative facts about this array are easy to miss and both break naive parsers:

1. **It is absent entirely from the system-message payload.** Row 14's syntax block goes `metadata` → `messages`
   with no `contacts` array at all. Code that reads `contacts[0].profile.name` to name the sender will fail on a
   `user_changed_number` event.
2. **`wa_id` and `from` are not the same value and need not match.** Rows 3 and 16 both state, of the user ID,
   "Note that a WhatsApp user's ID and phone number may not always match," and of the phone number, "This is the
   same value returned by the API as the `input` value when sending a message." Row 3's parameter table even
   gives `16505551234` for `<WHATSAPP_USER_ID>` against `+16505551234` for `<WHATSAPP_USER_PHONE_NUMBER>` — one
   without a leading `+`, one with. Identity must key on `wa_id`, and `from` must not be assumed E.164-normalised.

### 2.4 Fields common to a `messages[]` object

| Field path | Type | Presence | Meaning |
|---|---|---|---|
| `messages[].from` | String | always | WhatsApp user phone number |
| `messages[].id` | String | always | WhatsApp message ID, `wamid.` prefix |
| `messages[].timestamp` | String | always | Unix timestamp of webhook trigger |
| `messages[].type` | String | always | selects which sibling object is populated |
| `messages[].context` | Object | conditional | reply / UI-component / forwarded provenance — §2.6 |
| `messages[].referral` | Object | conditional | only if the message came via a Click to WhatsApp ad — §2.7 |
| `messages[].errors` | Array | conditional | only with `type` `unsupported` (row 2) |
| `messages[].group_id` | String | conditional | only for group messages (row 21) |

The `type` values evidenced by a dedicated reference page in this set are: `text`, `image`, `audio`, `video`,
`document`, `sticker`, `location`, `contacts`, `interactive`, `button`, `reaction`, `system`, `order`,
`unsupported`, `revoke`, `edit`. Row 21 (group) does not add a type; it adds `group_id` to an otherwise ordinary
typed message and shows `"type": "<MESSAGE_TYPE>"` as a placeholder. **No page in this set enumerates the full
`type` list in one place** — the list above is assembled from the existence of the per-type pages, which is why
§6 records it as a gap rather than a quotation.

### 2.5 Per-type objects, field by field

Every field below is verbatim from the named row. "optional" means the page marks it conditional or describes it
as omissible; "always" means the page's syntax block shows it unconditionally for that type.

| `type` | Object | Fields (type, presence) | Row |
|---|---|---|---|
| `text` | `text` | `body` (String, always) | 3 |
| `image` | `image` | `caption` (String, optional), `mime_type` (String), `sha256` (String), `id` (String), `url` (String) | 4 |
| `video` | `video` | `caption` (String, optional), `mime_type`, `sha256`, `id`, `url` (all String) | 6 |
| `document` | `document` | `caption` (String, optional), `filename` (String), `mime_type`, `sha256`, `id`, `url` | 7 |
| `audio` | `audio` | `mime_type`, `sha256`, `id`, `url` (String), `voice` (Boolean) — **no `caption`** | 5 |
| `sticker` | `sticker` | `mime_type`, `sha256`, `id`, `url` (String), `animated` (Boolean) — **no `caption`** | 8 |
| `location` | `location` | `address` (String), `latitude` (**number, unquoted**), `longitude` (**number, unquoted**), `name` (String), `url` (String) | 9 |
| `contacts` | `contacts[]` | see §2.5.1 | 10 |
| `interactive` | `interactive` | `type` = `list_reply` or `button_reply`; then `list_reply` {`id`, `title`, `description`} or `button_reply` {`id`, `title`} | 11 |
| `button` | `button` | `payload` (String), `text` (String) | 12 |
| `reaction` | `reaction` | `message_id` (String), `emoji` (String, **omitted if the user removes the reaction**) | 13 |
| `system` | `system` | `body` (String), `wa_id` (String, the **new** user ID), `type` = `user_changed_number` | 14 |
| `order` | `order` | `catalog_id` (String), `text` (String), `product_items[]` {`product_retailer_id` (String), `quantity` (number), `item_price` (number), `currency` (String)} | 15 |
| `unsupported` | `unsupported` | `type` (String) — the unsupported type; accompanied by `messages[].errors` | 16 |
| `revoke` | `revoke` | `original_message_id` (String) | 19 |
| `edit` | `edit` | `original_message_id` (String), `message` {`context`{`id`}, `type`, and the type's own object} | 20 |

Three details in that table are load-bearing and contradict the shape many integrations assume:

- **Media objects now carry a `url`.** Rows 4–8 all include `url` ("`<MEDIA_ASSET_URL>`") alongside `id`,
  `mime_type` and `sha256`. This is a change from the long-standing id-only media shape. Agent 020 (media
  download, URL expiry) must resolve whether that URL is directly usable and what its lifetime is — no page in
  *this* set says.
- **`latitude` and `longitude` are unquoted numbers**, while every timestamp in the message tree is a quoted
  String. A schema that types all webhook scalars as String will reject a location message.
- **`button.payload` and `button.text` carry the same placeholder** in row 12's syntax (`<BUTTON_LABEL_TEXT>` for
  both), so for a template quick-reply the payload is not documented as distinct from the visible label. For
  `interactive` replies, by contrast, `id` and `title` are genuinely distinct (row 11).

#### 2.5.1 The `contacts` message type

Row 10 prefaces its syntax with: "Many contact properties may be omitted if the WhatsApp user chooses not to
share them or if their device prevents sharing." So **every** field here is optional. `messages[].contacts` is an
array of objects with: `addresses[]` {`city`, `country`, `country_code`, `state`, `street`, `type`, `zip`},
`birthday`, `emails[]` {`email`, `type`}, `name` {`formatted_name`, `first_name`, `last_name`, `middle_name`,
`suffix`, `prefix`}, `org` {`company`, `department`, `title`}, `phones[]` {`phone`, `wa_id`, `type`}, `urls[]`
{`url`, `type`}. All String. Note the name collision: `value.contacts[]` (the sender) and
`value.messages[].contacts[]` (the shared contact cards) are different objects with the same key name at
different depths.

### 2.6 `context` — reply-to, product inquiry, and forwarded

`context` is one key carrying three different shapes. Rows 3, 11 and 12 show them:

| Shape | Fields | When | Row |
|---|---|---|---|
| Reply / UI component | `from` (business display phone number), `id` (the message replied to) | interactive reply, template quick-reply reply | 11, 12 |
| Product inquiry | `from`, `id`, `referred_product` {`catalog_id`, `product_retailer_id`} | user pressed **Message business** on a catalog/product message | 3 |
| Forwarded | `forwarded` (Boolean `true`) **or** `frequently_forwarded` (Boolean `true`) | message forwarded to the business | 3, 4, 6 |

The forwarding distinction is quantified in the syntax comments: `forwarded` is "only included if forwarded 5
times or less"; `frequently_forwarded` is "only included if forwarded more than 5 times". These are
**presence-only flags** — there is no count field and no `false` variant documented, so absence is the negative
case.

Forwarding context is shown on the text, image and video pages (rows 3, 4, 6). It is **not** shown in the syntax
of the audio, document, sticker, location, contacts or order pages. Whether that is a real constraint or a
documentation omission is unresolved; §6 records it.

### 2.7 `referral` — Click to WhatsApp ad attribution

Rows 3–10 all carry the same `referral` object, "only included if message sent via a Click to WhatsApp ad":
`source_url` (ad URL), `source_id` (ad ID), `source_type` (`"ad"`), `body` (ad primary text), `headline`,
`media_type` (`image` or `video`), `image_url` (only if an image ad), `video_url` (only if a video ad),
`thumbnail_url` (only if a video ad), `ctwa_clid` (ad click ID), `welcome_message` {`text`} (the ad greeting
text). All String.

One exclusion is stated twice on row 3, in both the parameter table and the example prose: **`ctwa_clid` is
omitted entirely for messages originating from an ad in WhatsApp Status** (WhatsApp Status ad placements). Any
attribution logic that requires a click ID will silently drop that placement's traffic.

`source_type` is only ever shown as the literal `"ad"` in this set. No other value is documented, so the
historically-cited `post` value is **not confirmed** by any page I read.

### 2.8 The `statuses` webhook

Row 18 is the authority. Field by field:

| Field path | Type | Presence | Meaning |
|---|---|---|---|
| `statuses[].id` | String | always | the `wamid.` of the business's outgoing message |
| `statuses[].status` | String | always | `sent`, `delivered`, `read`, `played`, `failed` |
| `statuses[].timestamp` | String | always | Unix timestamp of webhook trigger |
| `statuses[].recipient_id` | String | always | user phone number, **or a group ID** if sent to a group |
| `statuses[].recipient_type` | String | only if sent to a group | `"group"` |
| `statuses[].recipient_participant_id` | String | only if sent to a group | the group participant's phone number |
| `statuses[].recipient_identity_key_hash` | String | only if identity change check enabled | identity key hash |
| `statuses[].biz_opaque_callback_data` | String | only if set on the send request | the business's own correlation value |
| `statuses[].conversation` | Object | conditional — see below | |
| `statuses[].pricing` | Object | conditional — see below | |
| `statuses[].errors[]` | Array | "only included if failure to send or deliver message" | |

**Status values**, with Meta's WhatsApp-client equivalents, verbatim from row 18:

| Value | Meaning | WhatsApp UI equivalent |
|---|---|---|
| `sent` | message successfully sent from Meta's servers | one checkmark |
| `delivered` | message successfully delivered to the user's device | two checkmarks |
| `read` | message displayed in an open chat thread on the user's device | two blue checkmarks |
| `played` | the **first** time a voice message is played by the user's device | blue microphone |
| `failed` | failure to send or deliver | red error triangle |

**The delivery-status rule that costs support teams the most time**, stated verbatim on row 18: "A status is
considered read only if it has been delivered. In some cases, like when a user receives a message while in the
chat screen, the message is both delivered and read at the same time. In these cases, the 'delivered' webhook is
not sent because it's implied that the message was delivered since it was read. This behavior is due to internal
optimization."

So a `read` with no preceding `delivered` is normal and documented. Any Lynomia state machine that only reaches
"read" by transitioning out of "delivered" will strand those messages, and any agent-facing explanation that says
"delivered always precedes read" is wrong.

Row 18 also states the group triggers explicitly, and that `recipient_id` holds a **group ID** rather than a
phone number when the message went to a group, with the participant's number moved to
`recipient_participant_id`. Code that treats `recipient_id` as a phone number will mis-key group traffic.

#### 2.8.1 `conversation`

Fields: `id` (String), `expiration_timestamp` (String, Unix — "only included for `sent` status"), and `origin`
{`type`}. Presence, verbatim from the syntax comments: "(1) Only included with sent status, and one of either
delivered or read status. (2) **Omitted entirely for v24.0+ unless webhook is for a free entry point
conversation**."

`origin.type` — the conversation category — has seven documented values: `authentication`,
`authentication_international`, `marketing`, `marketing_lite` (Marketing Messages API for WhatsApp),
`referral_conversion` (free entry point conversation), `service`, `utility`.

#### 2.8.2 `pricing`

| Field | Type | Values |
|---|---|---|
| `pricing.billable` | Boolean | **deprecated** — see §5 |
| `pricing.pricing_model` | String | `CBP` (conversation-based pricing; "will only be set to this value if the webhook was sent before July 1, 2025"), `PMP` (per-message pricing) |
| `pricing.type` | String | `regular` (billable), `free_customer_service` (utility template or non-template message inside a customer service window), `free_entry_point` (inside an open free entry point window) |
| `pricing.category` | String | `authentication`, `authentication-international`, `marketing`, `marketing_lite`, `referral_conversion`, `service`, `utility` |

Presence: "only included with sent status, and one of either delivered or read status." Row 18's own example
prose sharpens this — the `pricing` object "can only appear in one or the other" of the delivered and read
webhooks. So billing reconciliation cannot assume pricing arrives on a specific status; it must take whichever of
the two carries it.

**The field is `pricing.type`, not `pricing_type`.** And note the inconsistent spelling across the two
enumerations: the conversation category uses `authentication_international` (underscore) while the pricing
category uses `authentication-international` (hyphen). Both are quoted directly from row 18's parameter table.
This is Meta's inconsistency, not a transcription error, and a shared normalisation helper that assumes one
spelling will drop the other.

#### 2.8.3 `statuses[].errors[]`

`code` (Integer), `title` (String), `message` (String), `error_data` {`details` (String)}, `href` (String, link
to the error-code documentation). Row 18 states twice that `title` and `message` carry **the same value** — so
showing both to an agent is duplicated noise, and `error_data.details` is the only field with distinct
explanatory content.

### 2.9 The three places errors appear

Row 2 enumerates them, and this is the single most useful structural fact for an error-handling design:

| Location | Means | Reference |
|---|---|---|
| `entry.changes.value.errors` | system-, app- or account-level problem prevented a request being processed | row 17 |
| `entry.changes.value.messages[].errors` | an **incoming** message could not be processed; `type` is set to `unsupported` | row 16 |
| `entry.changes.value.statuses[].errors` | an **outgoing** message failed to send or deliver | row 18 |

The shapes are nearly identical but not identical: rows 17 and 18 include `href`; row 16's syntax block does
**not** include `href` on the incoming-message error object. All three carry `code`, `title`, `message` and
`error_data.details`.

`value.errors` is the one most integrations never implement, because it arrives on the `messages` field but
describes neither a message nor a status — row 17's example is a bare `value` with `metadata` and `errors` and
nothing else. A parser that requires `messages` or `statuses` to be present will drop it, and with it every
account-level rate-limit warning.

### 2.10 Which fields a WABA can subscribe to

Row 1 lists **19 subscribable webhook fields**, and this is the authoritative enumeration:

| Field | What it delivers (Meta's description, condensed) |
|---|---|
| `messages` | inbound messages from users and delivery status of outbound messages |
| `account_alerts` | changes to a phone number's messaging limit, business profile, and Official Business Account status |
| `account_review_update` | the outcome of a policy review of a WABA |
| `account_update` | partner-led verification, authentication-international eligibility, primary location, policy/terms violations, offboarding, reconnection, deletion, partner sharing |
| `automatic_events` | detected purchase or lead events in Click to WhatsApp ad chats, if opted in |
| `business_capability_update` | WABA or business-portfolio capability changes (messaging limits, phone number limits) |
| `history` | chat-history synchronisation for WhatsApp Business app customers onboarded by a solution provider |
| `message_template_components_update` | changes to a template's components |
| `message_template_quality_update` | changes to a template's quality score |
| `message_template_status_update` | changes to the status of an existing template |
| `partner_solutions` | status changes for Multi-Partner Solutions |
| `payment_configuration_update` | payment-configuration changes for Payments API India and Brazil |
| `phone_number_name_update` | display-name verification outcomes |
| `phone_number_quality_update` | changes to a phone number's throughput level |
| `security` | changes to a phone number's security settings (two-step verification / PIN) |
| `smb_app_state_sync` | contact synchronisation for onboarded WhatsApp Business app users |
| `smb_message_echoes` | messages sent from the WhatsApp Business app or a linked device by onboarded customers |
| `template_category_update` | changes to a template's category |
| `user_preferences` | changes to a user's marketing-message preferences |

**Note the field name.** Meta's field is `message_template_status_update`, **not** `template_status_update`. The
brief for this agent used the shorter form; it is not a real field name and must not be used in Lynomia
documentation or code.

**Subscription mechanism and permissions** (row 1): subscription is per-field, through **App Dashboard →
WhatsApp → Configuration** (or **App Dashboard → Use cases → Customize → Configuration** for apps created with
the "Connect with customers through WhatsApp" use case). Permissions: `whatsapp_business_messaging` for the
`messages` field, `whatsapp_business_management` for **all other fields**. Partners need advanced access via App
Review before business customers can grant these during onboarding. Row 1 **does not** name a Graph API endpoint
or state whether subscription is app-level or WABA-level, and **does not** state which fields are on by default —
all three are gaps (§6).

Row 1 also documents webhook **overrides**: an alternate endpoint can be used for certain fields for a WABA or a
business phone number, which is how a partner gives each onboarded customer its own endpoint.

### 2.11 The account-level webhooks — what tells a business its WABA is in trouble

This is the set that matters for a support desk, enumerated exactly.

**`account_update` (row 24)** is the big one. `value` carries `event` plus one conditional sub-object. The 15
documented `event` values:

| `event` | Meaning | Sub-object carried |
|---|---|---|
| `ACCOUNT_DELETED` | WABA was deleted | — |
| `ACCOUNT_RESTRICTION` | WABA restricted due to policy violations | `restriction_info[]` |
| `ACCOUNT_VIOLATION` | WABA violated Meta policies or terms | `violation_info` {`violation_type`} |
| `AD_ACCOUNT_LINKED` | onboarded to Marketing Messages API, partner given ad-account access | `waba_info` {`waba_id`, `ad_account_linked`, `owner_business_id`} |
| `AUTH_INTL_PRICE_ELIGIBILITY_UPDATE` | eligible for authentication-international rates | `auth_international_rate_eligibility` {`exception_countries[]`{`country_code`,`start_time`}, `start_time`} |
| `BUSINESS_PRIMARY_LOCATION_COUNTRY_UPDATE` | primary business location set | top-level `country` (ISO 3166-1 alpha-2) |
| `DISABLED_UPDATE` | WABA violated Meta policies or terms | `ban_info` {`waba_ban_state`, `waba_ban_date`} |
| `MM_LITE_TERMS_SIGNED` | accepted MM API for WhatsApp terms of service | `waba_info` {`waba_id`, `owner_business_id`} |
| `PARTNER_ADDED` | WABA shared with a Solution Partner | `waba_info` |
| `PARTNER_APP_INSTALLED` | business customer granted the app permissions | `waba_info` + `partner_app_id` |
| `PARTNER_APP_UNINSTALLED` | business customer deauthenticated/uninstalled the app | `waba_info` + `partner_app_id` |
| `PARTNER_CLIENT_CERTIFICATION_STATUS_UPDATE` | partner-led business verification approved/rejected/discarded | `partner_client_certification_info` {`client_business_id`, `status`, `rejection_reasons[]`} |
| `PARTNER_REMOVED` | WABA unshared with a Solution Partner | `waba_info`, and `disconnection_info` {`reason`, `initiated_by`} when the business used both the WhatsApp Business app and Cloud API |
| `VOLUME_BASED_PRICING_TIER_UPDATE` | volume-based pricing tier updated | `volume_tier_info` {`tier_update_time`, `pricing_category`, `tier`, `effective_month`, `region`} |
| `ACCOUNT_OFFBOARDED` (marked **New**) | offboarded due to a device change or phone number reregistration | — |
| `ACCOUNT_RECONNECTED` (marked **New**) | reconnected after a device change or phone number reregistration | — |

Two events, `ACCOUNT_VIOLATION` and `DISABLED_UPDATE`, carry **the same description on row 24** — "Indicates WABA
violated Meta policies or terms" — and are distinguished only by their sub-object. That ambiguity is recorded in
§6.

`ban_info.waba_ban_state`: `DISABLE` (WABA is disabled), `REINSTATE` (reinstated), `SCHEDULE_FOR_DISABLE`
(scheduled to be disabled). `waba_ban_date` is a **String** and row 24's example is the human-readable
`"April 17, 2025"` — not a Unix timestamp, unlike every other date in this tree.

`restriction_info[]` carries `restriction_type`, `expiration` (Integer Unix) and `remediation` (String, "only
when remediation steps are available"). The nine documented `restriction_type` values:
`RESTRICTED_ADD_PHONE_NUMBER_ACTION`, `RESTRICTED_BIZ_INITIATED_AND_USER_INITIATED_CALLING`,
`RESTRICTED_BIZ_INITIATED_MESSAGING`, `RESTRICTED_BUSINESS_INITIATED_CALLING`,
`RESTRICTED_CUSTOMER_INITIATED_MESSAGING`, `RESTRICTED_DIRECT_SEND_UTILITY_TEMPLATES`,
`RESTRICTED_USER_INITIATED_CALLING`, `RESTRICTED_USER_INITIATED_CALLING_CALL_BUTTON_HIDDEN`,
`RESTRICTED_UTILITY_TEMPLATES`. `RESTRICTED_BIZ_INITIATED_MESSAGING` and
`RESTRICTED_CUSTOMER_INITIATED_MESSAGING` are the two that stop a Lynomia inbox working, and they are
independent — a WABA can be blocked from initiating while still able to reply, or the reverse.

`violation_info.violation_type` is **not enumerated** on row 24; it defers to a separate "Violations" page
(`/documentation/business-messaging/whatsapp/policy-enforcement-violations`), with `ADULT` given only as an
example value. That page was not fetched, so the violation vocabulary is **not checked** — it belongs to Agent 027
or 028.

`disconnection_info.reason`: `ACCOUNT_DISCONNECTED`, `BUSINESS_DOWNGRADE`, `CHANGE_NUMBER`,
`COMPANION_INACTIVITY`, `PRIMARY_INACTIVITY`, `USER_RE_REGISTERED`. `initiated_by`: `SYSTEM` or `USER`. Row 24
attaches concrete durations: `COMPANION_INACTIVITY` is "a companion device was inactive for approximately 30
days"; `PRIMARY_INACTIVITY` is "the primary device was inactive for approximately 14 days".

**`account_alerts` (row 22)** — `value` is `entity_type`, `entity_id`, and `alert_info` {`alert_severity`,
`alert_status`, `alert_type`, `alert_description`}. `entity_type`: `BUSINESS`, `PHONE_NUMBER`,
`CURRENT_STATUS_ID` (a change to the phone number's business profile). `alert_severity`: `CRITICAL` (a rejection
or denial), `INFORMATIONAL` (no action needed), `WARNING` (action may be needed). `alert_status`: `ACTIVE`,
`NONE`. `alert_type` has six documented values: `INCREASED_CAPABILITIES_ELIGIBILITY_DEFERRED`,
`INCREASED_CAPABILITIES_ELIGIBILITY_FAILED`, `INCREASED_CAPABILITIES_ELIGIBILITY_NEED_MORE_INFO`,
`OBA_APPROVED`, `OBA_REJECTED`, `PROFILE_PICTURE_LOST`. Unusually, row 22 enumerates **eight exact
`alert_description` strings** — these are the literal sentences Meta sends, and they are the right raw material
for a troubleshooting article, because a business will paste one of them into a support ticket verbatim.

**`account_review_update` (row 23)** — `value.decision` only: `APPROVED`, `REJECTED`, `PENDING`, `DEFERRED`. Row
23 states that for `REJECTED`, `PENDING` and `DEFERRED` the WABA "cannot be used with our APIs" — so this single
field is the difference between a working and a dead integration.

**`phone_number_quality_update` (row 30)** — despite the name, row 30 says it "notifies you of changes to a
business phone number's **throughput level**". `value` is `display_phone_number`, `event`, `old_limit` (only for
messaging-limit changes), `current_limit`, `max_daily_conversations_per_business`. `event` has only two
documented values: `ONBOARDING` (number still being registered) and `THROUGHPUT_UPGRADE`. Tier values for the
three limit fields: `TIER_50`, `TIER_250`, `TIER_2K`, `TIER_10K`, `TIER_100K`, `TIER_NOT_SET` (number has not
sent a message yet), `TIER_UNLIMITED`. **There is no quality-rating field** (`GREEN`/`YELLOW`/`RED`) on this page
at all — see §6, because that is a real change from what this webhook was historically understood to carry, and
a documentation claim about "quality rating webhooks" would now be wrong.

**`business_capability_update` (row 25)** — `value` is `max_daily_conversation_per_phone` (Integer),
`max_daily_conversations_per_business`, `max_phone_numbers_per_business` and `max_phone_numbers_per_waba`.
`max_phone_numbers_per_business` is "only included if `max_daily_conversation_per_phone` is set to `250`";
`max_phone_numbers_per_waba` is included only if it is **not** `250`. Row 25 types
`max_daily_conversations_per_business` as Integer but enumerates its values as the **strings** `TIER_250`,
`TIER_2K`, `TIER_10K`, `TIER_100K`, `TIER_UNLIMITED`, while its own example payload shows the integer `2000` — a
direct self-contradiction, recorded in §6.

**`message_template_status_update` (row 26)** — `value` is `event`, `message_template_id` (Integer),
`message_template_name`, `message_template_language`, `reason`, `message_template_category`, plus `disable_info`
{`disable_date`} if disabled, `other_info` {`title`, `description`} if locked/unlocked, and `rejection_info`
{`reason`, `recommendation`} **only if rejected with an `INVALID_FORMAT` reason**. The 14 `event` values:
`APPROVED`, `ARCHIVED`, `UNARCHIVED`, `DELETED`, `DISABLED`, `FLAGGED`, `IN_APPEAL`, `LIMIT_EXCEEDED`, `LOCKED`,
`PAUSED`, `PENDING`, `REINSTATED`, `PENDING_DELETION`, `REJECTED`. `reason` values: `ABUSIVE_CONTENT`,
`CATEGORY_NOT_AVAILABLE` (marked Deprecated), `INCORRECT_CATEGORY`, `INVALID_FORMAT`, `NONE` (template was
paused), `PROMOTIONAL`, `SCAM`, `TAG_CONTENT_MISMATCH` — and **`null`, not a string, if the template is scheduled
for deletion**. `other_info.title` values: `FIRST_PAUSE`, `SECOND_PAUSE`, `RATE_LIMITING_PAUSE`, `UNPAUSE`,
`DISABLED`. `ARCHIVED` carries a concrete consequence: archived templates "are scheduled for deletion after 28
days unless unarchived".

**`message_template_quality_update` (row 27)** — `previous_quality_score`, `new_quality_score`,
`message_template_id`, `message_template_name`, `message_template_language`. Score values: `GREEN` (high),
`YELLOW` (medium), `RED` (low), `UNKNOWN` (pending). This is where quality scoring actually lives, at template
level — not on `phone_number_quality_update`.

**`template_category_update` (row 29)** — `message_template_id`, `message_template_name`,
`message_template_language`, then either the *impending*-change trio `correct_category`, `new_category`,
`category_update_timestamp`, or the *completed*-change pair `previous_category`, `new_category`. Note
`new_category` appears in **both** branches with different meanings, which is a genuine trap.

**`message_template_components_update` (row 28)** — `message_template_id`, `message_template_name`,
`message_template_language`, `message_template_element` (body text), plus `message_template_title` (if a text
header), `message_template_footer` (if a footer), and `message_template_buttons[]`
{`message_template_button_type`, `message_template_button_text`, `message_template_button_url` (url buttons),
`message_template_button_phone_number` (phone buttons)}.

**`phone_number_name_update` (row 31)** — `display_phone_number`, `decision`, `requested_verified_name`,
`rejection_reason`. `decision`: `APPROVED`, `DEFERRED`, `PENDING`, `REJECTED`. `rejection_reason`:
`NAME_EMPLOYEE_ISSUE`, `NAME_ENDCLIENT_NOTRELATED`, `NAME_FORMAT_UNACCEPTABLE`, `NAME_INDIVIDUAL_ISSUE`,
`NAME_NOT_CONSISTENT`, `UNKNOWN`, and **`null` if the name was accepted**.

**`security` (row 32)** — `display_phone_number`, `event`, `requester` (Meta Business Suite user ID). `event`:
`PIN_CHANGED`, `PIN_RESET_REQUEST`, `PIN_REQUEST_SUCCESS`. This is the only webhook that tells a platform
operator that someone turned off two-step verification on a connected number — directly relevant to Lynomia's
WhatsApp reconnection story.

**`user_preferences` (row 33)** — message-style envelope plus `user_preferences[]` {`wa_id`, `detail`,
`category` (`"marketing_messages"`), `value`, `timestamp`}. `value`: `stop` or `resume`. Row 33 adds a scoping
note: it "triggers only when a user stops or resumes marketing messages. It does not trigger when a user
indicates **Interested** or **Not interested** feedback through the **Offers and announcements** setting." For
Lynomia's campaigns this is the marketing opt-out signal, and it is per `wa_id`.

**`partner_solutions` (row 34)** — `event`, `solution_id`, `solution_status`. Documented statuses: `DRAFT`,
`INITIATED`, `ACTIVE`, `REJECTED`, `DEACTIVATED`. Note `entry[].id` here is a **business portfolio ID**, not a
WABA ID.

**`automatic_events` (row 35)** — message-style envelope plus `automatic_events[]` {`id` (a `wamid.`),
`event_name`, `timestamp`, `ctwa_clid`, and `custom_data` {`currency`, `value`} for purchase events only}.

---

## 3. Error codes and failures

Only codes that appear verbatim on a page in the register are listed. Cells read `not stated` where the page does
not say. No code here is inferred, and no code is carried over from memory.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Row |
|---|---|---|---|---|---|---|
| 130429 | not stated | `Rate limit hit` | "Message failed to send because there were too many messages sent from this phone number in a short period of time" (that text is the `error_data.details` example) | not stated on this page | not stated | 17 |
| 131049 | not stated | `This message was not delivered to maintain healthy ecosystem engagement.` | `error_data.details`: "In order to maintain a healthy ecosystem engagement, the message failed to be delivered." Arrives as a `failed` status. | not stated on this page | message not delivered; red error triangle in the WhatsApp client | 18 |
| 131050 | not stated | not stated | Appears **only** as the example value for `<ERROR_CODE>` in row 18's parameter table. Row 18 does not pair a title with it. | not stated | not stated | 18 |
| 131051 | not stated | `Message type unknown` | "Cloud API does not support the message type." Arrives as an incoming `unsupported` message. | not stated on this page | not stated | 16 |
| 131060 | not stated | `This message is currently unavailable.` | "The message is currently unavailable. This typically occurs when a WhatsApp user messages a business onboarded with a WhatsApp Business app phone number, for the first time." | not stated on this page | not stated | 16 |

**No subcodes anywhere.** Not one page in this register exposes an error subcode field. The webhook error object
is `code` / `title` / `message` / `error_data.details` / `href` and nothing more. Any Lynomia error taxonomy that
expects a subcode from a webhook will find none — subcodes belong to the synchronous Graph API error envelope
(Agent 025), not to webhooks.

**`href` is a relative path, and its form is inconsistent.** Row 18's parameter table gives
`/docs/whatsapp/cloud-api/support/error-codes/`; row 18's own failed example and row 17's example both give
`/documentation/business-messaging/whatsapp/support/error-codes`. The first is the pre-restructure path. So
`href` must not be surfaced to an agent as a clickable link without being resolved against a current base, and it
does not identify the specific code — it points at the index.

**The authoritative code list is elsewhere.** Every error page here links to
`/documentation/business-messaging/whatsapp/support/error-codes` as the catalogue. That page is **not checked** by
this agent and is the correct scope for Agents 005 and 028. This report deliberately enumerates only the five
codes that appear in webhook reference pages, because that is the boundary of my brief.

**The `unsupported.type` vocabulary** (row 16) is a different kind of failure surface and is fully enumerated —
19 values for the kind of message Cloud API could not represent: `button`, `edit`, `errors`, `gif`,
`group_invite`, `hsm`, `image`, `interactive`, `keep_in_chat`, `link_preview`, `list`, `location`,
`media_placeholder`, `order`, `pin`, `poll_creation`, `poll_update`, `product`, `reaction`. Note that `image`,
`location`, `order`, `reaction`, `interactive` and `button` appear here **as well as** being supported types —
meaning a specific variant of a supported type can still arrive as `unsupported`. `poll_creation` and
`poll_update` are the common real-world cases: a user creating a poll in a chat produces an `unsupported` message
that Lynomia must render as something other than an empty bubble.

Row 16 also documents a trigger worth calling out: "You use the API to send a message to a number already in use
with the API. When the number is already in use, Cloud API sends the webhook to the owner of the recipient
number." That is a cross-tenant delivery of an `unsupported` webhook.

---

## 4. Limits and numbers

Only numbers a source states.

| Number | What it governs | Row |
|---|---|---|
| **3 MB** | maximum webhook payload size | 1 |
| **7 days** | Meta retries a failed webhook delivery "with decreasing frequency until the request succeeds, for up to 7 days" | 1 |
| **up to 3** | webhooks per outgoing message (sent, delivered, read) | 2 |
| **5 forwards** | boundary between `context.forwarded` (5 times or less) and `context.frequently_forwarded` (more than 5) | 3 |
| **30 days** | window within which a user can react to a business message and produce a reaction webhook | 13 |
| **2 days** | window within which a user can revoke a sent message | 19 |
| **15 minutes** | window within which a user can edit a sent message | 20 |
| **28 days** | after archival, a template is scheduled for deletion unless unarchived | 26 |
| **~30 days** | companion-device inactivity producing `COMPANION_INACTIVITY` disconnection | 24 |
| **~14 days** | primary-device inactivity producing `PRIMARY_INACTIVITY` disconnection | 24 |
| **50 / 250 / 2,000 / 10,000 / 100,000** | messaging-limit tiers behind `TIER_50`…`TIER_100K` | 30 |
| **250 / 2000 / 10000 / 100000 / -1** | integer messaging-limit values on `max_daily_conversation_per_phone`; `-1` means unlimited | 25 |
| **July 1, 2025** | `pricing.pricing_model` is `CBP` only for webhooks sent before this date; `PMP` thereafter | 18 |
| **February 2026** | `phone_number_quality_update.old_limit`, `.current_limit` and `business_capability_update.max_daily_conversation_per_phone` will be removed | 25, 30 |

Retries go "to all apps that have subscribed to webhooks (and their appropriate fields) for the WhatsApp Business
account," and row 1 states plainly that "these retries can result in duplicate webhook notifications." Meta
documents **no ordering guarantee** anywhere in this register — see §6.

---

## 5. Version and deprecation notes

| Item | Version/date | Statement | Row |
|---|---|---|---|
| `statuses[].conversation` | **v24.0+** | "Omitted entirely for v24.0+ unless webhook is for a free entry point conversation." | 18 |
| `conversation.id` | **v24.0+** vs **v23.0 and lower** | v24.0+: unique per free entry point window. v23.0 and lower: unique **per message**, unless within an open free entry point window. | 18 |
| `pricing.billable` | future versioned release | "The `billable` property will be deprecated in a future versioned release. Use `pricing.type` and `pricing.category` together to determine whether a message is billable and, if so, its billing rate." | 18 |
| `pricing.pricing_model` = `CBP` | before 2025-07-01 | set to `CBP` only for webhooks sent before July 1, 2025; `PMP` (per-message pricing) otherwise | 18 |
| `phone_number_quality_update.old_limit` | **removed February 2026** | "This parameter will be removed in February, 2026. Use `max_daily_conversations_per_business` instead." | 30 |
| `phone_number_quality_update.current_limit` | **removed February 2026** | same wording | 30 |
| `business_capability_update.max_daily_conversation_per_phone` | **removed February 2026** | "This parameter will be removed in February, 2026. Use `max_daily_conversations_per_business` instead." | 25 |
| `message_template_status_update.reason` = `CATEGORY_NOT_AVAILABLE` | marked "(Deprecated)" | "Indicates an authentication templates for an unsupported region." | 26 |
| `account_update` events `ACCOUNT_OFFBOARDED`, `ACCOUNT_RECONNECTED` | marked "**New:**" | offboarding/reconnection after a device change or phone number reregistration | 24 |

**February 2026 is four months away from the date checked.** Three fields a Lynomia integration may currently
read are scheduled for removal, and the replacement in all three cases is
`max_daily_conversations_per_business`. This is the one hard deadline in this report and it belongs in the
Phase 4 contract, not just in an article.

The `conversation`-object change at v24.0 is the quieter hazard: an installation that derives conversation
grouping or billing attribution from `conversation.id` gets a field that was per-message in v23.0, is per-window
in v24.0, and is **absent altogether** in v24.0 for everything except free entry point conversations.

---

## 6. Ambiguities and gaps

Stated plainly, as the contract requires.

1. **No page enumerates the `messages[].type` values.** Row 2 says each type "has a dedicated reference, linked
   in the menu on the left" and lists none inline. The 16-value list in §2.4 is assembled from the existence of
   per-type pages in the index (row 36), not quoted from a page. A canonical `type` enumeration does not exist in
   Meta's documentation as far as this register goes.

2. **WhatsApp Flows replies are undocumented in this entire reference set.** The `interactive` page (row 11)
   documents exactly two `interactive.type` values, `list_reply` and `button_reply`. There is **no** `nfm_reply`,
   no `flow_token`, and no flow-response shape on any of the 39 pages retrieved; a grep across all of them for
   `nfm_reply`, `flow_token` and `"flow"` returns nothing. The product index (row 36) contains no Flows section at
   all — only two unrelated Embedded Signup pages whose titles happen to contain "flow". I probed
   `developers.facebook.com/docs/whatsapp/flows/...` and got HTTP 404. **I therefore cannot confirm the field name
   a Flow response arrives under, and I will not guess it.** This matters directly: Lynomia ships a flow builder
   (Agent 037's scope). Agent 012's brief covers template flows and should resolve it; until then, any claim about
   Flow response payloads is unverified.

3. **`ACCOUNT_VIOLATION` and `DISABLED_UPDATE` carry identical descriptions** on row 24 — both "Indicates WABA
   violated Meta policies or terms." Meta does not say how they differ in meaning or which arrives when. They can
   only be told apart by their sub-objects (`violation_info` vs `ban_info`).

4. **`business_capability_update.max_daily_conversations_per_business` contradicts itself.** Row 25 types it
   Integer, enumerates its values as the strings `TIER_250`…`TIER_UNLIMITED`, and shows the integer `2000` in its
   own example payload. A parser cannot be written against this field from the documentation alone.

5. **Row 18's second example is internally inconsistent.** The prose says "This example v24.0 webhook describes a
   marketing message that has been displayed in the WhatsApp client (that is, 'read')", but the JSON beneath it
   has `"status": "sent"`. One of the two is wrong and Meta does not say which.

6. **`phone_number_quality_update` no longer documents a quality rating.** The page is named for quality and its
   own description says it reports **throughput level**; its `event` enumeration is only `ONBOARDING` and
   `THROUGHPUT_UPGRADE`, and there is no `GREEN`/`YELLOW`/`RED` field and no downgrade event. Whether a quality
   *downgrade* produces any webhook at all is **not stated anywhere in this register**. For a support desk this
   is the single most consequential silence in the documentation: it is not established that a business is
   notified by webhook when its number's quality falls.

Further gaps, each a thing Meta does not state:

7. **No ordering guarantee.** Row 1 covers payload size, retries and duplicates, and says nothing about ordering.
   Nothing in the register states that `sent` precedes `delivered`, or that webhooks arrive in event order.
   Combined with the documented delivered-skipping (§2.8) and documented duplicates, a correct consumer must be
   order-independent and idempotent on `wamid`. Meta does not say this; it follows from what Meta does say.
8. **No subscription API.** Row 1 documents only the App Dashboard UI. It names no Graph endpoint, does not say
   whether subscription is app-level or WABA-level, and does not state which fields are enabled by default.
   (Agent 026's scope.)
9. **`violation_info.violation_type` is not enumerated** — row 24 defers to a policy-enforcement page outside
   this register. `ADULT` is the only example. Not checked.
10. **`context.forwarded` is shown only for text, image and video.** Whether a forwarded document, audio,
    sticker, location or contact card carries forwarding context is not stated.
11. **`played` status presence rules are undocumented.** Row 18 defines `played` and lists a voice-message
    trigger but never says whether `conversation`, `pricing` or the group fields accompany it.
12. **No signature or verification material in this register.** `X-Hub-Signature-256`, the verification
    handshake and `hub.challenge` appear nowhere in these 39 pages; row 1 covers mTLS and IP ranges only, and
    defers signature handling to Graph API's own webhooks document. That is Agent 026's scope and must not be
    answered from this report.
13. **`source_type` has one documented value.** Only `"ad"` appears. The `post` value sometimes attributed to
    `referral.source_type` is **not confirmed** by any page here.

---

## 7. What Lynomia users would ask

The questions this area actually produces for a support desk, each answerable from a row above.

| The question an agent or customer asks | What answers it |
|---|---|
| "The customer says they read my message but Lynomia still shows it as sent — is it broken?" | No. Row 18: a `delivered` webhook is **not sent** when a message is delivered and read simultaneously. A `read` with no `delivered` is documented behaviour. |
| "Why do some messages never show a read receipt?" | Read receipts depend on the user's privacy setting; nothing in this register promises a `read` webhook for every message. Not stated — do not claim otherwise. |
| "Why did this message fail with no explanation?" | `statuses[].errors[]` carries `code`, `title`/`message` (identical to each other) and `error_data.details`. The detail text is the only non-duplicated content and is what should be surfaced. |
| "Our WABA stopped sending. What happened?" | `account_update` with `ACCOUNT_RESTRICTION` (check `restriction_info[].restriction_type` — `RESTRICTED_BIZ_INITIATED_MESSAGING` blocks initiating, `RESTRICTED_CUSTOMER_INITIATED_MESSAGING` blocks replying), or `DISABLED_UPDATE` with `ban_info.waba_ban_state`, or `account_review_update` with `REJECTED`/`PENDING`/`DEFERRED`. |
| "Will we be warned before the account is disabled?" | `ban_info.waba_ban_state` has `SCHEDULE_FOR_DISABLE`, and `message_template_status_update` has `FLAGGED` ("at risk of being disabled"). Both are documented early warnings. |
| "Why can't we raise our messaging limit?" | `account_alerts` with `alert_type` `INCREASED_CAPABILITIES_ELIGIBILITY_DEFERRED` / `_FAILED` / `_NEED_MORE_INFO`, and `alert_description` contains the exact sentence Meta sends. |
| "Our template stopped working." | `message_template_status_update` `event` — `PAUSED`, `DISABLED`, `REJECTED`, `ARCHIVED` (deleted after 28 days), `LIMIT_EXCEEDED` — with `reason` and, for `INVALID_FORMAT`, a `rejection_info.recommendation` that tells the author what to change. |
| "Why did our template's category change by itself?" | `template_category_update`, which fires both for an impending automated change and for a completed one. |
| "Who turned off two-step verification on our number?" | `security` with `event` `PIN_RESET_REQUEST` / `PIN_REQUEST_SUCCESS` / `PIN_CHANGED` and a `requester` user ID. |
| "Our display name was rejected — why?" | `phone_number_name_update.rejection_reason`, five named reasons plus `UNKNOWN`. |
| "A customer says they unsubscribed but we still messaged them." | `user_preferences` with `value` `stop`, keyed on `wa_id`. Row 33: it does **not** fire for "Not interested" feedback, so an opt-out through that path produces no webhook. |
| "The contact appears twice / under a different number." | `wa_id` and `from` need not match (row 3), and `from` may carry a leading `+` where `wa_id` does not. Identity must key on `wa_id`. |
| "Why is this incoming message blank?" | `type: unsupported` — most often `poll_creation`/`poll_update` — with code `131051` or `131060`. |
| "We got a webhook for a message we did not send." | Row 16: sending to a number already in use with the API delivers the webhook to the owner of the recipient number. |
| "Which ad did this conversation come from?" | `referral` — but `ctwa_clid` is **absent** for WhatsApp Status ad placements (row 3). |
| "Will our billing data change?" | Yes: `pricing.billable` is deprecated in favour of `pricing.type` + `pricing.category`; `pricing_model` moved `CBP` → `PMP` on 2025-07-01; and `conversation` is omitted entirely from v24.0 except for free entry point conversations. |
| "Did we miss a webhook?" | Retries continue for up to 7 days, reach every subscribed app, and may duplicate (row 1). Duplicate handling on `wamid` is required, not optional. |

**One standing caution for whoever writes the articles.** Three of the five error codes in §3 are the only ones
these webhook pages name, and two of those (`131050`, and the `code`/`title` pairing generally) are incompletely
specified on the page itself. The real catalogue is the error-codes page, which this agent did not fetch. Per
§6.2, the WhatsApp error articles must take their codes from that catalogue via Agents 005 and 028 — not from
this report, and not from the five examples above.
