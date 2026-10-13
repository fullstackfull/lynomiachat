---
agent: 009
scope: WhatsApp message template CREATION — template object, components, buttons, parameters, every documented limit, creation-time validation, multi-language
confidence: high
sources_normative: 13
sources_observational: 2
---

# 009 — WhatsApp message template creation

All facts below come from the rows in §1. Every numeric limit is quoted from a page I read; where Meta does
not state a number, the cell reads **not stated** and it stays that way. Meta's own docs were in the middle of
a path migration on the date checked: the live canonical tree is
`developers.facebook.com/documentation/business-messaging/whatsapp/**`, while `developers.facebook.com/docs/whatsapp/**`
still serves content (sometimes the same page under a different title). Both are normative; §5 records the
version mismatches between them.

## 1. Source register

| Row | Source URL | Page title | Product | API/version context | Date checked | Status |
|---|---|---|---|---|---|---|
| R1 | https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates | Template fundamentals | WhatsApp Business Management API | create example `POST /v23.0/{WABA_ID}/message_templates`; status example uses `<API_VERSION>` | 2026-10-13 | normative |
| R2 | https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates/components | Template components | WhatsApp Business Management API | none stated | 2026-10-13 | normative |
| R3 | https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/message_templates/ | WhatsApp Business Account `message_templates` (Graph API reference) | Graph API | reference labelled v26.0; GET sample request uses v16.0 | 2026-10-13 | normative |
| R4 | https://developers.facebook.com/docs/whatsapp/message-templates/guidelines | Template fundamentals (same content as R1 under the guidelines path) | WhatsApp Business Management API | none stated | 2026-10-13 | normative |
| R5 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/authentication-templates/authentication-templates/ | Authentication templates | WhatsApp Business Platform | `POST /<WABA_ID>/upsert_message_templates`; `GET /<WABA_ID>/message_template_previews` | 2026-10-13 | normative |
| R6 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-categorization | Template categorization | WhatsApp Business Platform | dated policy changes, no API version | 2026-10-13 | normative |
| R7 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/components | Template components (current path) | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| R8 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/media-card-carousel-templates/ | Media card carousel templates | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| R9 | https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates/supported-languages | Supported Languages | WhatsApp Business Management API | none stated | 2026-10-13 | normative |
| R10 | https://developers.facebook.com/documentation/business-messaging/whatsapp/flows/guides/sendingaflow | Send a Flow message | WhatsApp Flows | none stated | 2026-10-13 | normative (thin on creation) |
| R11 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/limited-time-offer-templates | Limited-time offer templates | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| R12 | https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/coupon-templates/ | Coupon code templates | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| R13 | https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates/catalog-templates | Catalog templates | WhatsApp Business Management API | send example uses v19.0 | 2026-10-13 | normative |
| O1 | WebSearch result summaries over `developers.facebook.com` (authentication/OTP terms) | — | — | — | 2026-10-13 | **observational, unconfirmed** — snippet text only, page not read |
| O2 | WebSearch result summaries over `developers.facebook.com` (template text formatting) | — | — | — | 2026-10-13 | **observational, unconfirmed** — snippet text only, page not read |
| X1 | `…/templates/create-and-manage-templates`, `…/templates/` (index), `…/templates/catalog-templates` | — | — | — | 2026-10-13 | **not retrievable** — returned site navigation only; no content extracted |

## 2. The rules

### 2.1 The template object

A template is created with `POST /<WHATSAPP_BUSINESS_ACCOUNT_ID>/message_templates` (R1, R3). The response
returns `id`, `status` and `category` (R3). The edge does not support update: the Graph reference states
plainly "You can't perform this operation on this endpoint" for the POST-as-update case (R3) — editing is a
different endpoint and is Agent 010's scope.

| Field | Type | Rule |
|---|---|---|
| `name` | string | **Required.** Max **512** characters, "consisting of lowercase alphanumeric characters and underscores" (R1, R4). Not globally unique: the same name may be reused for a different language, and each one counts against the template limit (R1, R4). R12 phrases the same rule as "`name` must be unique, unless existing templates with the same name use a different language". |
| `language` | string | Required per R1; R3 does not mark it required. A language/locale code from the Supported Languages list (R1, R9). |
| `category` | enum | **Required.** `UTILITY`, `MARKETING`, `AUTHENTICATION` (R3). R1's examples use lowercase (`utility`, `marketing`, `authentication`); both casings appear in Meta's own examples. Category also drives pricing (R1). |
| `parameter_format` | enum | `NAMED` or `POSITIONAL` (R3). Defaults to positional when omitted (R1, R4). |
| `components` | array | Text, media and interactive components (R1). See §2.3. |
| `allow_category_change` | boolean | `true` lets the platform assign the category from its own guidelines and content analysis, which can stop `status` being set to `REJECTED` at creation for miscategorisation; if omitted, no category is auto-assigned and a miscategorised template may be rejected (R3). **R6 supersedes this**: since **9 April 2025** that behaviour is the default and the property "is no longer needed". See §6.1. |
| `message_send_ttl_seconds` | int64 | Time-to-live for a sent template; if the user stays offline past it, delivery retries stop (R3). Default, minimum and maximum: **not stated** (R3; R1 says TTL can be customised at creation but gives no value or range). |
| `library_template_name` | string | Listed in the reference with no description (R3). |
| `library_template_body_inputs` | object | Body inputs when creating from a Template Library template: boolean flags `add_contact_number`, `add_learn_more_link`, `add_security_recommendation`, `add_track_package_link`, plus `code_expiration_minutes` (int64) (R3). |
| `library_template_button_inputs` | array | Button inputs for library templates: `type`, `phone_number`, `url`, `base_url`, `url_suffix_example`, `otp_type`, `zero_tap_terms_accepted`, `supported_apps`, `booking_url`, `booking_management_url`, `notes` (R3). |
| `sub_category` | enum | `ORDER_DETAILS`, `ORDER_STATUS`, `RICH_ORDER_STATUS` (R3). |
| `product_set_id` | numeric string | Marked "[Coming soon]" / still in development (R3). |
| `creative_sourcing_spec` | object | ACO dimensions: `associated_product_set_id`, `is_primary_device_delivery_only` (R3). |
| `optimization_spec` | object | Ad-optimisation settings (`bid_strategy`, `optimization_goal`, `status`, `targeting`, `promoted_object`, `adset_schedule`, budgets, dates) (R3). Nesting is hard to confirm from the flattened reference page. |

### 2.2 Categories and what they constrain at creation

Three categories only (R6): `MARKETING` (most flexible; mixed-content and unclear-content templates default
here), `UTILITY` (must be non-promotional **and** either user-specific/user-requested or essential/critical),
`AUTHENTICATION` (most restrictive). R6 states authentication templates must use Template Library templates,
must carry a one-time-password button (copy-code or one-tap), must exclude URLs, media and emojis, and that
**parameters are limited to 15 characters**. Only authentication templates may send one-time passcodes.

Category is validated against content at creation. A category mismatch yields `status` `REJECTED` and a
`message_template_status_update` webhook with `event` `REJECTED` and `reason` `INCORRECT_CATEGORY` (R6).
Since 9 April 2025, a `UTILITY` template that WhatsApp judges to be marketing is **approved as `MARKETING`**
rather than rejected (R6).

### 2.3 Components

Body is the only required component (R2, R7). A template may have one text header, one body and one footer
(R7). The Graph reference's component `type` enum is wider than the guides document: `GREETING`, `HEADER`,
`BODY`, `FOOTER`, `BUTTONS`, `CAROUSEL`, `ALBUM`, `LIMITED_TIME_OFFER`, `CALL_PERMISSION_REQUEST`,
`TAP_TARGET_CONFIGURATION`, `ATTACHMENT`; the `format` enum is `TEXT`, `IMAGE`, `DOCUMENT`, `VIDEO`,
`LOCATION`, `GIF`, `COLLECTION` (R3). `GREETING`, `ALBUM`, `CALL_PERMISSION_REQUEST`,
`TAP_TARGET_CONFIGURATION`, `ATTACHMENT` and `COLLECTION` are **not documented in the component guides I read**
— they exist in the enum and nowhere else (see §6).

**HEADER** — optional, one per template (R7).

| Format | Rules |
|---|---|
| `TEXT` | `text`, max **60** characters; **1** parameter maximum; positional or named. Example required when it contains a parameter: `header_text` (positional) or `header_text_named_params` (named, `param_name` + `example`). "Do not use Markdown special characters in this component." (R2, R7) |
| `IMAGE` / `VIDEO` / `DOCUMENT` | Example asset must be uploaded with the **Resumable Upload API**; the returned asset handle is passed as `example.header_handle` (an array). No variables. File size limits: **not stated** (R2, R7). The example asset is reviewed as part of template review (R1, R4). |
| `GIF` | mp4 file, max **3.5 MB**; larger files display as video messages. Available **only for the Marketing Messages API** (R2, R7). |
| `LOCATION` | No creation parameters. Allowed **only** in `UTILITY` or `MARKETING` templates. Real-time locations not supported. Latitude, longitude, name and address are supplied at send time (R2, R7). |

**BODY** — required, one per template, text only. Max **1024** characters (R2, R7, R12, R13); **600** in
limited-time-offer templates, where variables count toward the limit (R11). Multiple parameters allowed; the
maximum number of body parameters is **not stated** (R7). Example object required when parameters are used:
`body_text` (positional) or `body_text_named_params` (named) (R2, R3, R7). R13 adds that positional body
example values are themselves capped at **1024** characters.

**FOOTER** — optional, one per template, directly after the body. Max **60** characters (R2, R7, R13).
Variables: R7 does not mention footer variables; R13 says footer `text` supports variables — unresolved,
see §6.3. Footers are **not supported at all** in limited-time-offer templates (R11).

**BUTTONS** — a single `BUTTONS` component holding a `buttons` array, up to **10** buttons across all types
(R2, R7). If there are more than **three**, WhatsApp displays two and a "See all options" button for the rest.
Four or more buttons, or a quick reply combined with another button type, **cannot be viewed on WhatsApp
desktop clients**; the recipient is prompted to open the message on a phone (R2, R7).

| Button type | Count | Text limit | Other creation rules |
|---|---|---|---|
| `QUICK_REPLY` | up to **10** | **25** chars (R12 adds "alphanumeric only") | Must be grouped: all quick replies together, before or after all non-quick-reply buttons. Mixed ordering causes an **API error** (R7). Send-time `index` sets display order. |
| `URL` | up to **2** | **25** chars | `url` max **2000** chars; **1** variable, appended at the **end** of the URL only; `example` array required when a variable is used; special characters must be percent-encoded at send time or the send can fail (R2, R7). |
| `PHONE_NUMBER` | **1** | **25** chars | `phone_number` max **20** characters (alphanumeric string). Some numbers with a leading zero after the country code lose that zero (R2, R7). |
| `COPY_CODE` | **1** | not customisable | `example` max **20** characters (R7, R12); **15** characters in limited-time-offer templates (R11). Value supplied at send time; R12 states send-time `coupon_code` is capped at 20. |
| `OTP` | not stated | not stated | A special kind of URL button for authentication templates. `otp_type` values documented: `ONE_TAP`, `COPY_CODE` (R5). One-tap (and zero-tap) require `supported_apps`, each entry with `package_name` and `signature_hash` (R5). |
| `FLOW` | not stated | not stated | Button type exists: "Use this type to specify the Flow to be sent with the message template." Either pass Flow JSON in the creation request or name/ID an already-published Flow — **R10 does not give the field names**. The Graph enum carries `flow_id` (int64), `flow_action` (`NAVIGATE`, `DATA_EXCHANGE`), `supported_apps`, `ttl_minutes` (int64) (R3). |
| `CATALOG` | not stated | `"View catalog"` in the example | Requires inventory in a Meta e-commerce catalog connected to the WABA. Template shows a fixed text header and sub-header; the thumbnail header image is chosen at send time via `action.thumbnail_product_retailer_id`, defaulting to the first item's image (R13). |
| `MPM` | not stated | non-customisable | Displays up to **30** products from a catalog, organised in up to **10** sections (R2, R7). |
| `SPM` | not stated | non-customisable | Mapped to one catalog product; no numeric limits stated (R2, R7). |
| `VOICE_CALL` | not stated | not stated | Places a WhatsApp call to the business when tapped; limits not stated (R2, R7). |
| `VIDEO_CALL`, `POSTBACK`, `BOOKING_STATUS`, `PAYMENT_REQUEST`, `REQUEST_CONTACT_INFO` | not stated | not stated | Present in the Graph API button `type` enum (R3) and **not documented in any guide page I read**. |

**CAROUSEL** (media card carousel, R8) — `MARKETING` only. A `body` component plus a `carousel` component
holding a `cards` array. **Minimum 2, maximum 10 cards**, and the count is fixed at creation: "An approved
template can only be used to send the same number of cards as defined during its creation." Every card must
have the same component structure. Card header is required, `format` `image` or `video`, with
`example.header_handle`. Card body is optional, but if any card has one, all cards must. Up to **two** buttons
per card, types may be mixed, with the same per-type limits (`quick_reply`/`url`/`phone_number` text 25,
`url` 2000 with one trailing variable, `phone_number` 20). Message-level body text is required, max **1024**,
supports variables, and the number of example strings must match the number of placeholders. A per-card body
limit of **160** characters appears on R8 **only in the send-time parameter table**, not in the creation
section — treat it as a send-time constraint until a creation-side page states it.

**LIMITED_TIME_OFFER** (R11) — `MARKETING` only, **no footer component**. `limited_time_offer.text` required,
max **16** characters; `limited_time_offer.has_expiration` optional boolean (true shows expiration details in
the delivered message). Body required, max **600** characters. `copy_code` button `example` required, max
**15** characters. `url` button `text` max 25, `url` max 2000 with one trailing variable. Optional header must
be `IMAGE` or `VIDEO` with `example.header_handle`.

**AUTHENTICATION** (R5) — body text is preset and non-customisable ("`<VERIFICATION_CODE>` is your
verification code"), rendered localised per language rather than authored. Optional security disclaimer
("For your security, do not share this code") via `add_security_recommendation` (boolean, BODY). Optional
expiration line ("This code expires in `<NUM_MINUTES>` minutes") via `code_expiration_minutes` (integer,
FOOTER); omitting it leaves the footer out. Exactly one button variant per template: one-tap autofill
(`otp_type` `ONE_TAP`), copy code (`otp_type` `COPY_CODE`), or no button at all (zero-tap — the client
broadcasts the code and the app captures it with a broadcast receiver). The upsert endpoint
`POST /<WABA_ID>/upsert_message_templates` takes `languages` (array) instead of `language`, and **does not
support** `language`, `text` or `autofill_text`. `autofill_text` is returned by
`GET /<WABA_ID>/message_template_previews` only; it is not a creation input. Linked-device security is on by
default, not configurable, Cloud API only.

### 2.4 Parameter (variable) syntax

Two formats, selected by `parameter_format` (R1, R4):

- **Positional** — the default. `{{1}}`, `{{2}}`, … "Positional parameters must be ordered array index
  numbers, starting from 1." Example values go in `example.body_text` / `example.header_text` in placeholder
  order. R7 notes an internal inconsistency: the syntax prose shows a flat array while the full example
  requests use a nested array (`[[ "value" ]]`).
- **Named** — `{{first_name}}`. "Parameters using the named format must be unique, single strings, composed of
  lowercase characters and underscores", wrapped in double curly brackets. Examples go in
  `example.body_text_named_params` / `example.header_text_named_params`, each entry an object with
  `param_name` and `example` (both required, R3). Example and send values may appear in any order.

An example value is required for **every** parameter at creation (R1, R4). The Graph reference is blunt:
"Templates will not be approved without examples" (R3). Meta does not translate template strings or example
parameters — the business supplies each language itself (R1, R4).

### 2.5 Formatting

The only formatting rule stated normatively on the creation pages I read is for the TEXT header: "Do not use
Markdown special characters in this component" (R2, R7). For **body, footer and button text, Meta's template
documentation states no formatting rules at all** — no statement that bold/italic/strikethrough/monospace
markers are allowed, none that they are forbidden, and nothing about emoji or newlines (R2, R7; searched in
O2 without result). Authentication templates are the one explicit prohibition: no URLs, media or emojis (R6).
See §6.2 — this is the single most load-bearing gap for a template-builder article and must not be filled by
inference.

### 2.6 Creation-time validation, restated as a checklist

From R1–R13, these are the rules Meta states are enforced when the template is submitted:

1. `name` ≤ 512 chars, lowercase alphanumerics and underscores only.
2. `category` must be one of the three and must match the content; mismatch → `REJECTED` / `INCORRECT_CATEGORY`
   (R6), except utility-judged-marketing which is approved as marketing since 9 April 2025.
3. Exactly one body; at most one text header, one footer, one `BUTTONS` component.
4. Character limits of §2.3 for header/body/footer/button text/url/phone/copy-code example.
5. An example value for every parameter; named parameter names unique, lowercase, underscores; positional
   indexes ordered from 1; example count must match placeholder count (R8).
6. Media header example must be an asset handle from the Resumable Upload API.
7. ≤ 10 buttons; ≤ 2 URL, ≤ 1 PHONE_NUMBER, ≤ 1 COPY_CODE, ≤ 10 QUICK_REPLY; quick replies grouped apart from
   other types or the API errors.
8. `LOCATION` header only for `UTILITY`/`MARKETING`; `GIF` header only via the Marketing Messages API.
9. Carousel: marketing only, 2–10 cards, identical card structure, card body all-or-none, ≤ 2 buttons per card.
10. Limited-time offer: marketing only, no footer, offer text ≤ 16, copy-code example ≤ 15, body ≤ 600.
11. Authentication: Template Library template, OTP button, no URL/media/emoji, parameters ≤ 15 chars,
    `code_expiration_minutes` within 1–90.
12. Templates are reviewed automatically on creation or after editing; only `APPROVED` templates can be sent;
    review "can take up to 24 hours" (R1, R4).

POST error codes listed by the Graph reference (R3): **100** invalid parameter, **80008** too many calls,
**131009** parameter value not valid, **192** invalid phone number, **200** permissions error, **368** action
deemed abusive or disallowed, **200002** HSM template creation failed, **139000** blocked by integrity.
These are the codes Lynomia should classify on template creation; nothing else is stated for this edge.

### 2.7 Multiple languages and how versions relate

- A language version is a **separate template object** that happens to share a name. Names are not unique
  precisely so that the same name can exist in several languages, and **each one counts against the template
  limit** (R1, R4).
- Meta performs **no translation**. Strings and example parameter values must be supplied in the target
  language (R1, R4).
- Language codes are lowercase language, optionally `_` plus uppercase region: `en`, `fr`, `ar`, `fil`,
  `en_US`, `en_GB`, `zh_CN`, `pt_BR`, `es_MX`, `fr_CA`, `de_CH`, `prs_AF`, `ky_KG`, `si_LK`. R9 does not state
  the format as a rule and does not give a total count — the format above is read off the table.
- The GET edge exposes `summary` fields `total_count`, `message_template_count`, `message_template_limit`
  (numeric value not stated on the page) and **`are_translations_complete`** (bool) (R3). That last field is
  the only documented signal that a template's language set is incomplete.
- Authentication templates have a dedicated bulk path: `POST /<WABA_ID>/upsert_message_templates` with a
  `languages` array (e.g. `["en_US","es_ES","fr"]`); if a template with the same name and language already
  exists it is updated, otherwise created, and the response returns `id`, `status` and `language` per language
  (R5). I found **no equivalent documented bulk/multi-language creation path for marketing or utility
  templates** on the pages I read.
- Send-time language resolution (whether `en` matches an `en_US` template) is Agent 011's scope; O1 reports
  that both language and locale forms are accepted at send time, but that is a search snippet and I did not
  read the page — **observational, unconfirmed**.

## 3. Error codes and failures

Creation-time only; send-time template failures belong to Agents 011/012.

| Code | Subcode | Title as Meta words it | Meaning | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 100 | not stated | Invalid parameter | A create/read/delete parameter is invalid | Fix the request field | nothing (no message sent) | R3 |
| 131009 | not stated | Parameter value is not valid | A supplied value fails validation (e.g. a limit in §2.3) | Correct the value | nothing | R3 |
| 80008 | not stated | Too many calls; retry later | Rate limit on the edge — consistent with 100 templates/WABA/hour | Back off and retry | nothing | R3 |
| 192 | not stated | Invalid phone number | Phone number in the request is invalid | Fix the number | nothing | R3 |
| 200 | not stated | Permissions error | Token lacks `whatsapp_business_management` or asset access | Fix token/role | nothing | R3 |
| 368 | not stated | The action attempted has been deemed abusive or is otherwise disallowed | Integrity/abuse block on the action | Appeal via Business Support | nothing | R3 |
| 200002 | not stated | HSM template creation failed | Template creation rejected by the HSM layer | Re-check content against §2.6 | nothing | R3 |
| 139000 | not stated | Blocked by integrity | Integrity block | Appeal via Business Support | nothing | R3 |
| 190 | not stated | Invalid OAuth 2.0 access token | Token expired/invalid (GET and DELETE lists) | Re-authenticate | nothing | R3 |

Rejection *reasons* (as opposed to API error codes) arrive on the `message_template_status_update` webhook;
the only reason value stated on the pages I read is `INCORRECT_CATEGORY` (R6). The full rejection-reason
enumeration is Agent 010's scope.

## 4. Limits and numbers

Every number below is stated by its source row. Nothing is inferred.

| Limit | Value | Source |
|---|---|---|
| Templates created per WABA per hour | 100 | R1, R4 |
| Templates per WABA, unverified business portfolio | 250 | R1, R4 |
| Templates per WABA, verified portfolio with ≥1 WABA holding a business phone number with an approved display name | up to 6,000 | R1, R4 |
| `name` length | 512 characters | R1, R4, R12, R13 |
| Header TEXT length | 60 characters | R2, R7, R12 |
| Header TEXT parameters | 1 | R2, R7 |
| Header GIF file size | 3.5 MB (mp4) | R2, R7 |
| Body length | 1024 characters | R2, R7, R12, R13 |
| Body length, limited-time-offer templates | 600 characters | R11 |
| Body example value length (positional) | 1024 characters | R13 |
| Body parameter count | **not stated** | R7 |
| Footer length | 60 characters | R2, R7, R13 |
| Buttons per template, all types | 10 | R2, R7 |
| Buttons shown before "See all options" | 2 shown when >3 defined | R2, R7 |
| QUICK_REPLY buttons | 10 | R2, R7 |
| URL buttons | 2 | R2, R7 |
| PHONE_NUMBER buttons | 1 | R2, R7 |
| COPY_CODE buttons | 1 | R2, R7, R12 |
| Button text (quick reply / URL / phone) | 25 characters | R2, R7, R8, R11 |
| URL button `url` | 2000 characters | R2, R7, R8, R11 |
| URL button variables | 1, appended at the end | R2, R7, R8, R11 |
| `phone_number` | 20 characters | R2, R7, R8 |
| COPY_CODE `example` | 20 characters | R7, R12 |
| COPY_CODE `example`, limited-time-offer templates | 15 characters | R11 |
| Send-time `coupon_code` | 20 characters | R12 |
| `limited_time_offer.text` | 16 characters | R11 |
| Carousel cards | min 2, max 10 | R8 |
| Buttons per carousel card | 2 | R8 |
| Carousel card body (send-time table only) | 160 characters | R8 |
| MPM products / sections | 30 products, 10 sections | R2, R7 |
| `code_expiration_minutes` | integer 1–90 | R5 |
| Authentication template parameter length | 15 characters | R6 |
| Template review duration | up to 24 hours | R1, R4 |
| Utility→marketing recategorisation notice | 1 day (0 if the business has been warned, from 16 Apr 2025) | R6 |
| Category review request window | 60 days | R6 |
| Miscategorisation enforcement durations | rate limiting ≥ 7 days; utility restriction 7 days (30 for repeat); portfolio restriction 30 days | R6 |
| `message_template_limit` numeric value | **not stated** on the reference page | R3 |
| `message_send_ttl_seconds` default/min/max | **not stated** | R1, R3 |
| Image / video / document header file size | **not stated** | R2, R7 |

## 5. Version and deprecation notes

- The pages disagree on version: the Graph reference is labelled **v26.0** but its GET sample uses **v16.0**
  (R3); Template fundamentals creates against **v23.0** (R1); the catalog send example uses **v19.0** (R13).
  Any Lynomia article that quotes a version from Meta's examples will be quoting a stale one. Cite the field
  contract, not the example's version.
- **9 April 2025** — a `UTILITY` template judged to be marketing is approved as `MARKETING`; the
  `allow_category_change` opt-in became the default behaviour and "is no longer needed" (R6).
- **1 July 2024** — recurring utility→marketing recategorisation process begins (R6).
- **16 April 2025** — businesses already warned for misuse get instant recategorisation with no notice (R6).
- **1 October 2024** — marketing/utility templates that should be authentication get advance notice, then
  `status` changes to `REJECTED` on the first day of the following month (R6).
- **15 June 2026** — keyboard suggestions enabled by default for all authentication templates on iOS 26+, no
  integration required (R5).
- `product_set_id` is marked "[Coming soon]" and still in development (R3) — do not document it as usable.
- O1 reports that from **v21.0** `package_name` and `signature_hash` must be defined inside `supported_apps`
  for one-tap and zero-tap templates. R5 shows `supported_apps` carrying exactly those two fields but states
  no version. **Observational, unconfirmed** as a version boundary.

## 6. Ambiguities and gaps

**6.1 `allow_category_change` has two live, conflicting descriptions.** The Graph API reference (R3) still
documents it as a meaningful opt-in whose absence risks `REJECTED`. The categorization guide (R6) says the
behaviour has been the default since 9 April 2025 and the property is no longer needed, and it does **not**
state what `false` or omission now does. A template builder cannot tell from Meta's docs whether sending
`allow_category_change: false` today opts *out* of auto-assignment or is simply ignored. Record the ambiguity;
do not resolve it.

**6.2 Body/footer/button text formatting is undocumented.** No page I read states whether WhatsApp's
`*bold*`, `_italic_`, `~strikethrough~` or monospace markers, emoji, or newlines are permitted in template
body text, nor whether they survive review. The only normative statements are "no Markdown special characters"
in the TEXT header (R2, R7) and "no URLs, media, emojis" for authentication templates (R6). O2's search
returned a Meta interactive-template example whose body *parameter* value is asterisk-wrapped (`*Ski Trip*`),
which hints asterisks render as bold — **observational, unconfirmed, and about a send-time parameter value,
not authored template text.** Any Lynomia claim here needs either a page I did not find or an explicit
"Meta does not document this".

**6.3 Footer variables.** R7 does not mention footer variables; R13 says the catalog template's footer `text`
supports variables. Unresolved. The safe statement is "Meta documents footer variables for catalog templates
only."

**6.4 COPY_CODE example length is 20 or 15 depending on the template type** — 20 generally (R7, R12), 15 in
limited-time-offer templates (R11). Likely a genuine per-type rule rather than a contradiction, but neither
page acknowledges the other.

**6.5 Six component types and five button types exist only in the Graph enum.** `GREETING`, `ALBUM`,
`CALL_PERMISSION_REQUEST`, `TAP_TARGET_CONFIGURATION`, `ATTACHMENT`, `COLLECTION` (format) and the buttons
`VIDEO_CALL`, `POSTBACK`, `BOOKING_STATUS`, `PAYMENT_REQUEST`, `REQUEST_CONTACT_INFO` appear in R3 with no
guide page, no limits and no example. Their existence is normative; their behaviour is undocumented.

**6.6 FLOW button creation fields are not documented on the Flows page.** R10 confirms the button type and
says you may pass Flow JSON or name a published Flow, but its "Sample request" for creation is empty and it
gives no field names, no per-template button count, no text limit, and no statement on combining FLOW with
other button types. `flow_id`, `flow_action`, `ttl_minutes` come from the Graph enum (R3) without descriptions.

**6.7 Maximum body parameter count is not stated anywhere.** Neither is any rule about a variable appearing at
the start or end of the body, adjacent variables, or a ratio of parameter count to text length. These rules
circulate widely in third-party BSP documentation; **none of them is in Meta's documentation as of
2026-10-13**. Do not publish them.

**6.8 Media header file size limits are not stated** for IMAGE, VIDEO or DOCUMENT on the component pages
(only GIF's 3.5 MB). The applicable limits are probably the media-upload limits — Agent 019's scope — but no
creation page says so.

**6.9 Zero-tap specifics are incomplete.** R5 describes zero-tap behaviour but gives neither the `otp_type`
value for it nor any documentation of `zero_tap_terms_accepted`, which exists only as a
`library_template_button_inputs` field name in R3. O1 adds that zero-tap is Android-only and that autofill
buttons are disabled after `code_expiration_minutes` or 10 minutes when absent — **observational,
unconfirmed** (snippet only; R5 states no default).

**6.10 Three pages returned navigation only** (X1): `templates/create-and-manage-templates`, the templates
index, and `templates/catalog-templates` on the new path. Anything those pages uniquely hold — most likely a
consolidated creation/management walkthrough and MPM template creation — is **not checked**. MPM is covered
here only by the two numbers on R2/R7 (30 products, 10 sections).

**6.11 Per-category body length.** 1024 is stated by the generic component pages and by coupon/catalog pages;
600 by the LTO page. Whether any other template type narrows 1024 is not checked.

## 7. What Lynomia users would ask

These are the support questions this surface generates, and they map directly onto a template-builder article.

| Question | Answered by |
|---|---|
| "Why was my template rejected the moment I submitted it?" | §2.2, §2.6, §3 — category mismatch (`INCORRECT_CATEGORY`), missing examples, integrity blocks (368/139000) |
| "Why does the builder refuse my template name?" | 512 chars, lowercase alphanumerics and underscores only (§2.1) |
| "Can I make the text bold / add an emoji?" | §6.2 — Meta does not document this; the one firm rule is no Markdown in the TEXT header, and no emoji in authentication templates |
| "Why can't I put a variable in the footer?" | §2.3, §6.3 — documented for catalog templates only |
| "My body is 1,100 characters and it won't save." | 1024 (600 for limited-time offers), variables counted (§4) |
| "I added four buttons and my colleague on WhatsApp Web sees nothing." | §2.3 — 4+ buttons, or quick replies mixed with another type, are not viewable on desktop |
| "Why did my quick-reply ordering throw an API error?" | §2.3 — quick replies must be grouped apart from other button types |
| "Why does my tracking URL break for some customers?" | URL button variable must be the trailing segment and percent-encoded at send time (§2.3) |
| "Why can't I add a Learn more link to my OTP template?" | §2.2 — authentication templates exclude URLs, media and emoji; parameters ≤ 15 chars |
| "How do I offer this template in Arabic and English?" | §2.7 — same name, one template per language, each counts against the limit, and Lynomia must supply the Arabic strings and examples; Meta translates nothing |
| "How many templates can we have?" | 250 unverified / up to 6,000 verified, 100 created per hour (§4) |
| "Our utility template became marketing and now costs more." | §2.2, §5 — recategorisation timeline, 60-day review window, enforcement ladder |
| "How long until it's approved?" | up to 24 hours (§4) |
| "Can I change an approved template's number of carousel cards?" | No — the count is fixed at creation (§2.3) |
