---
agent: 012
scope: WhatsApp template media headers, document/location headers, every button type, carousels and Flows — and their send-time constraints
confidence: medium
sources_normative: 16
sources_observational: 1
---

# Agent 012 — Template media headers, documents, buttons, Flows and their send-time constraints

All sources were read read-only over HTTPS on **2026-10-13**. No Meta API was called, no credential was
used, no form was submitted. Every numeric limit, field name and error code below is quoted from a Meta page
in the register; where a page is silent the cell says so rather than guessing.

**One structural finding before the detail.** Meta has migrated the WhatsApp developer corpus from
`developers.facebook.com/docs/whatsapp/**` to `developers.facebook.com/documentation/business-messaging/whatsapp/**`.
The two canonical pages Lynomia's own code and docs would most likely cite —
`/docs/whatsapp/cloud-api/guides/send-message-templates` and `/docs/whatsapp/cloud-api/reference/messages` —
now return, respectively, a "This page has moved" stub (S1) and a schema page whose `TemplateMessage`,
`template`, `components` and button objects have been reduced to bare names with no properties (S2). The
template send contract is no longer documented where almost every third-party integration guide points. This
has direct consequences for Phase 5 and is restated in §6.

---

## 1. Source register

| # | Source URL | Page title | Product | API/version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| S1 | `developers.facebook.com/docs/whatsapp/cloud-api/guides/send-message-templates` | Template messages | WhatsApp Cloud API | none; redirect stub only | 2026-10-13 | normative (but content-free) |
| S2 | `developers.facebook.com/docs/whatsapp/cloud-api/reference/messages` | Send Message (`POST /{Version}/{Phone-Number-ID}/messages`) | WhatsApp Cloud API | `{Version}` placeholder, base `graph.facebook.com` | 2026-10-13 | normative |
| S3 | `developers.facebook.com/documentation/business-messaging/whatsapp/llms.txt` | WhatsApp business-messaging documentation index | WhatsApp (all) | none | 2026-10-13 | normative (index) |
| S4 | `…/documentation/business-messaging/whatsapp/templates/overview` | Template fundamentals — Overview | WhatsApp Business Management API | `POST /<API_VERSION>/<WABA_ID>/message_templates` | 2026-10-13 | normative |
| S5 | `…/templates/components.md` | Template components | WhatsApp Business Management API | version not stated | 2026-10-13 | normative |
| S6 | `…/templates/template-media.md` | Template media | WhatsApp Business Management + Cloud API | `POST /<API_VERSION>/<WABA_ID>/message_templates` | 2026-10-13 | normative |
| S7 | `…/direct-send/media-headers.md` | Media message headers | WhatsApp **Direct Send API (beta)** | beta | 2026-10-13 | normative |
| S8 | `…/business-phone-numbers/media.md` | Media | WhatsApp Cloud API | `POST /<API_VERSION>/<PHONE_NUMBER_ID>/media` | 2026-10-13 | normative |
| S9 | `…/templates/authentication-templates/authentication-templates.md` | Authentication templates | WhatsApp Business Management API | Upsert Message Templates API | 2026-10-13 | normative |
| S10 | `…/templates/authentication-templates/autofill-button-authentication-templates.md` | One-tap autofill authentication templates | WhatsApp Cloud API + Android SDK | examples v23.0 | 2026-10-13 | normative |
| S11 | `…/templates/authentication-templates/zero-tap-authentication-templates.md` | Zero-tap authentication templates | WhatsApp Cloud API + Android SDK | legacy fields ≤ v20.0, removed at v21.0 | 2026-10-13 | normative |
| S12 | `…/templates/marketing-templates/coupon-templates.md` | Coupon code templates | WhatsApp Business Management + Cloud API | version not stated | 2026-10-13 | normative |
| S13 | `…/templates/marketing-templates/media-card-carousel-templates.md` | Media card carousel templates | WhatsApp Business Management + Cloud API | syntax v23.0, example request v25.0 | 2026-10-13 | normative |
| S14 | `…/catalogs/catalog-template-messages.md` | Catalog template messages | WhatsApp Cloud API (Commerce) | send example v19.0 | 2026-10-13 | normative |
| S15 | `…/catalogs/mpm-template-messages.md` | Multi-product message template messages | WhatsApp Cloud API (Commerce) | v23.0 | 2026-10-13 | normative |
| S16 | `…/templates/utility-templates/location-templates.md` | Location templates | WhatsApp Business Management + Cloud API | version not stated | 2026-10-13 | normative |
| S17 | `…/flows/guides/sendingaflow` and `…/flows/guides/sendingaflow.md` | Send a Flow message | WhatsApp Flows | version not stated | 2026-10-13 | normative |
| O1 | search-engine synthesis of Meta pages for `flow_id` / `flow_action` / `navigate_screen` | — | — | — | 2026-10-13 | **observational, unconfirmed** |

`developers.facebook.com/docs/whatsapp/flows/reference/flowstemplates` returned **HTTP 404** on 2026-10-13.
It is not a source; it is recorded as a gap in §6.

---

## 2. The rules

### 2.1 Media headers: creation uses a handle, send uses an id or a link

These are two different mechanisms against two different APIs, and conflating them is the single most common
integration error in this area.

**At template creation** (S4, S6): you upload the example asset to the **Resumable Upload API**, which returns
an asset handle, and you put that handle in the HEADER component's `example.header_handle` array —
`{"type": "HEADER", "format": "IMAGE", "example": {"header_handle": ["4::aW..."]}}` — in a
`POST /<API_VERSION>/<WABA_ID>/message_templates` request. S4 states the asset you supply here "is reviewed as
part of template review": it is a sample for the human reviewer, not the asset your customers receive.
S6's own wording says the Resumable Upload API "returns a media ID" which you "pass as the `header_handle`
value"; Meta uses "media ID" and "handle" interchangeably on that page even though the value is a resumable
upload handle, not a `/media` id. Recorded as an ambiguity (§6).

**At send time** (S6): you set `"type": "template"`, and the header component carries a parameter whose `type`
is `image`, `video` or `document`, containing a media object. S2 and S7 both state the rule for that object:
**"Either `id` or `link` is required."** `id` is a media id from `POST /<PHONE_NUMBER_ID>/media`; `link` is a
URL on your own server. S6: "If you're using link, your asset must be on a publicly accessible server or the
message will fail to send," and "Meta recommends that you upload your media assets and use their IDs when
sending messages," because it reduces errors and avoids requests to your public server.

So: **neither is unconditionally required — exactly one is.** Nothing in S2, S6 or S7 forbids `link`. The
"required when" question in the brief resolves as: a handle is required at creation for IMAGE/VIDEO/GIF/DOCUMENT
headers; an `id` or `link` is required at send for the same headers; a media id is *de facto* required for
carousel card headers because S13 documents only `id` there (see §2.5).

### 2.2 Header formats and what each allows

From S5. A template has at most one header.

| `format` | Creation requirement | Send-time requirement | Notes stated by Meta |
|---|---|---|---|
| `TEXT` | `text` required, max 60 chars; 1 parameter allowed, example via `header_text_named_params` (named) or `header_text` (positional) | text parameter if the header is parameterised | "Avoid Markdown special characters" |
| `IMAGE` | `example.header_handle` from Resumable Upload API | media object with `id` or `link` | formats/size **not stated on S5 or S6** |
| `VIDEO` | same | same | formats/size **not stated on S5 or S6** |
| `GIF` | same | same | **Marketing Messages API only.** GIFs are MP4 files up to 3.5 MB; larger files display as video messages |
| `DOCUMENT` | same | same | `filename` **not mentioned** on S5/S6 (see §2.4) |
| `LOCATION` | no example block; header takes no parameters at creation | header parameter `type: "location"` with a `location` object | UTILITY or MARKETING categories only; real-time locations not supported |

### 2.3 Image/video/document formats and size limits — what is actually documented, and where it is not

This is the most important caveat in the report. **S5, S6 and S7 — the three pages that document template and
message media headers — state no file formats, no size limits, no dimensions and no durations for header
media.** S7 says so explicitly for Direct Send. S6 omits them. S5 gives a size only for GIF (3.5 MB).

The full media table lives on S8, which documents the **Cloud API `/media` upload endpoint and media
messages**, not template header creation:

| Category | Max size (S8) | MIME types (S8) |
|---|---|---|
| Audio | 16 MB | `audio/aac`, `audio/amr`, `audio/mpeg`, `audio/mp4`, `audio/ogg` (OPUS codecs only, mono input only — base `audio/ogg` is not supported) |
| Document | 100 MB | `text/plain`, `application/vnd.ms-excel`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, `application/msword`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `application/vnd.ms-powerpoint`, `application/vnd.openxmlformats-officedocument.presentationml.presentation`, `application/pdf` |
| Image | 5 MB; must be 8-bit, RGB or RGBA | `image/jpeg`, `image/png` |
| Sticker | 100 KB static / 500 KB animated | `image/webp` (sticker messages only) |
| Video | 16 MB; H.264 video and AAC audio only | `video/3gpp`, `video/mp4` |

**Lynomia must document these as the `/media` upload limits, which is what they are.** Applying the 5 MB image
figure to a Resumable Upload template-creation asset is an inference, not a documented rule, and no page in the
register supports it. If Lynomia needs the creation-side limits it must find the Resumable Upload API page —
which S3's index does not list under this corpus (§6).

### 2.4 Document headers and filename handling

`filename` is documented in exactly one place in the register: **S7**, the Direct Send beta page, where it is
"optional for `document` headers". S5, S6 and S2 do not mention a filename field for template document headers
at all. S8 gives the document MIME list and the 100 MB `/media` ceiling.

Practical reading for Lynomia: a document header is created with a `header_handle` like any other media header
and sent with `id` or `link`; whether the recipient-visible filename can be set on a **template** document
header is **not stated** by any page checked. Do not document a template `filename` field as supported. (This
is a likely source of real support tickets: a PDF arriving with a machine-generated name.)

### 2.5 Location headers

From S16, corroborated by S5. A location template's header is `{"type": "HEADER", "format": "LOCATION"}` and
takes no example at creation. At send time the header component carries one parameter of `type: "location"`
with a nested `location` object:

| Field | Required | Notes |
|---|---|---|
| `latitude` | required | decimal degrees, string |
| `longitude` | required | decimal degrees, string |
| `name` | optional | |
| `address` | optional | |

S16: "The location (latitude, longitude, name, address) is specified at send time, not at template creation
time." Only `UTILITY` or `MARKETING` templates may include a location header. Real-time locations are not
supported. Tapping the map opens the user's default map app at the coordinates. S16 lists no client-version or
platform restriction, and no beta label. S5 shows the format as lowercase `location` in one syntax block and
uppercase `LOCATION` in its example — a casing ambiguity in Meta's own page (§6).

### 2.6 Buttons — creation fields, send-time payloads and the combination rules

From S5 unless noted. A template has one `buttons` array, **up to 10 buttons in total across all types**.

| Button type | Creation fields | Per-template max | Send-time payload |
|---|---|---|---|
| `QUICK_REPLY` | `text` (max 25) | 10 (shares the 10 total) | `{"type":"button","sub_type":"quick_reply","index":<n>,"parameters":[{"type":"payload","payload":"…"}]}` — S13 confirms `payload` is optional and is returned in the `messages.button.payload` webhook |
| `URL` | `text` (max 25), `url` (max 2000), `example` array required when the URL contains a variable | 2 | `{"type":"button","sub_type":"url","index":<n>,"parameters":[{"type":"text","parameter_name":…,"text":"<suffix>"}]}` |
| `PHONE_NUMBER` | `text` (max 25), `phone_number` (alphanumeric, max 20) | 1 | none — static |
| `COPY_CODE` | `example` (max 20) | 1 | `{"type":"button","sub_type":"copy_code","index":<n>,"parameters":[{"type":"coupon_code","coupon_code":"<≤20 chars>"}]}` (S12) |
| `OTP` | `otp_type`, `supported_apps`; becomes a `url` button after creation (S10, S11) | not stated | `sub_type: "url"` with a `text` parameter carrying the OTP (S10, S11) |
| `MPM` | `type: "MPM"`, `text` | 1 (S15 requires exactly one BUTTONS component with one object) | `sub_type: "mpm"`, `index: 0`, `parameters:[{"type":"action","action":{thumbnail_product_retailer_id, sections[]}}]` (S15) |
| `CATALOG` | `type: "CATALOG"`, `text` | not stated | `sub_type: "CATALOG"` (uppercase on S14), `index: 0`, `parameters:[{"type":"action","action":{thumbnail_product_retailer_id}}]` — parameters optional |
| `SPM` | non-customizable, mapped to a catalog product | not stated | not stated on S5 |
| `VOICE_CALL` | `text` (example: "Call"); places a WhatsApp call to the business | not stated | not checked — S5 defers to separate calling documentation |
| `FLOW` | **not documented on any page read** (§2.8) | not stated | `sub_type: "flow"`, `index: "0"`, `parameters:[{"type":"action","action":{flow_token, flow_action_data}}]` (S17) |

S5 does not cover `FLOW`, `CATALOG` or `APP` buttons, which is why those rows draw on S14/S15/S17.

**Grouping rule (S5), and it is enforced.** Quick-reply buttons must be contiguous and grouped separately from
non-quick-reply buttons. Valid: `QR, QR, URL, PHONE` or `URL, PHONE, QR, QR`. Invalid: `QR, URL, QR` or
`URL, QR, URL`. "Incorrect grouping returns an API error" — S5 does not give the code.

**Rendering consequences (S5).** With more than 3 buttons, two display and the rest sit behind a "See all
options" button. With 4 or more buttons, or a quick reply combined with another type, the message **cannot be
viewed on WhatsApp desktop**; the user is prompted to open it on a phone. This is a user-visible degradation
Lynomia should document, not a failure.

**Dynamic URL suffix (S5).** A URL button supports exactly 1 variable, appended to the **end** of the URL. The
`example` array must include a sample value. The URL including the variable is capped at 2000 characters.
Send-time values must be percent-encoded; S5 lists space `%20`, `:` `%3A`, `|` `%7C`, `ç` `%C3%A7`, `ñ`
`%C3%B1`, and warns that "unencoded characters can cause send failures." No error code is given.

### 2.7 Authentication templates: copy code, one-tap, zero-tap

From S9 (creation), S10 (one-tap), S11 (zero-tap).

Creation goes through the **Upsert Message Templates API** with `category: "AUTHENTICATION"` and a `languages`
array (S9: "the singular `language` field is not supported"). Body text is fixed preset copy and cannot be
customised. Optional modifiers: `add_security_recommendation` (boolean, BODY) and `code_expiration_minutes`
(integer, FOOTER, min 1, max 90). S9 notes `text` and `autofill_text` are **not supported in upsert** —
S10/S11 document them for the standard creation path, both max 25 characters, defaulting to localized strings
("Copy Code", "Autofill"). The button is submitted as `type: "otp"` with an `otp_type`, and **after creation a
GET shows the button type as `url`** (S10, S11) — a real trap for anyone round-tripping a template definition.

| Variant | `otp_type` | Extra requirements | Platform |
|---|---|---|---|
| Copy code | `COPY_CODE` (S9) | none | all |
| One-tap autofill | `one_tap` (S10 lowercase) / `ONE_TAP` (S9 uppercase) | `supported_apps` (up to 5) each with `package_name` and `signature_hash`; app-side handshake | **Android only** |
| Zero-tap | `zero_tap` (S11) | `zero_tap_terms_accepted` **required, boolean** — if `false` the template is not created; plus `supported_apps`; plus a broadcast receiver | **Android only** |

`package_name`: required, max 224 chars, at least one dot, each segment starts with a letter, chars `a-zA-Z0-9_`
(e.g. `com.example.luckyshrub`). `signature_hash`: required, **exactly 11 characters** from `a-zA-Z0-9+/=`
(e.g. `K8a/AINcGX7`), computed via Google's app-hash instructions or `sms_retriever_hash_v9.sh`.

**Send-time payload is identical for all three variants** (S10, S11): a `body` component with one `text`
parameter carrying the OTP, **and** a `button` component with `sub_type: "url"`, `index: 0` and one `text`
parameter carrying the same OTP. S10/S11 both state the one-time password **must appear twice in the payload**
and may be **at most 15 characters**. URLs, media and emojis are not supported in authentication templates.

**The handshake (one-tap and zero-tap).** Before sending, the business app sends an intent with action
`com.whatsapp.otp.OTP_REQUESTED` to `com.whatsapp` and `com.whatsapp.w4b`, carrying a UUID `request_id`. One-tap
delivery additionally requires an activity with intent filter `com.whatsapp.otp.OTP_RETRIEVED`; zero-tap
additionally requires a broadcast receiver on the same action with `android:exported="true"`. SDK:
`com.whatsapp.otp:whatsapp-otp-android-sdk:1.0.0`.

**Eligibility checks (S10, S11), and the graceful degradation they produce.** WhatsApp verifies: the handshake
happened within 10 minutes (or within `code_expiration_minutes` if set); the template's `package_name` matches
the intent creator (`getCreatorPackage`); no other `supported_apps` entry handshook in the same window; the
signature hash matches the installed app; the autofill button text is present; and the required activity /
receiver is declared. **Any failure silently downgrades the button** — zero-tap falls back to one-tap where
possible, one-tap falls back to copy code, and non-Android recipients always get copy code. Nothing fails; the
user just gets a different button. SDK-level handshake errors: `HANDSHAKE_ID_MISSING`,
`HANDSHAKE_ID_INVALID_FORMAT`, `HANDSHAKE_ID_MISMATCH`.

### 2.8 Flows

From S17. **Meta's own documentation is incomplete here.** The "Sample request" block under "Create a message
template with a Flow" is **empty on the live page** as of 2026-10-13.

What S17 does state normatively:
- Prerequisites: the business must be **verified** and maintain high message quality.
- "A new button type called FLOW is available."
- A Flow is attached to a template either by passing its Flow JSON in the creation request, or by referencing
  **an already published Flow by ID or name**.
- Flow IDs are stored in the template, so renaming a Flow does not break existing templates.
- The template `status` must be `APPROVED`, not `PENDING`, before sending.
- Send-time payload: `{"type":"button","sub_type":"flow","index":"0","parameters":[{"type":"action","action":{"flow_token":…,"flow_action_data":{…}}}]}`.
  `flow_token` is **optional, default `"unused"`**. `flow_action_data` is optional, a JSON object carrying the
  data payload for the first screen.

What is **not stated** on any page read: the FLOW button's creation field names, which of `flow_id` /
`flow_name` / `flow_json` are mutually exclusive, defaults, whether `flow_action` and `navigate_screen` apply
to template buttons at all, whether the referenced Flow must be published or may be draft, whether
`data_exchange` requires a configured Flow endpoint for the template path, how many FLOW buttons a template may
have, and whether FLOW combines with other button types. S17 explicitly confines its `flow_action`
(`navigate` | `data_exchange`, default `navigate`) and `flow_action_payload` discussion to **user-initiated
interactive messages**, not template buttons.

O1 (observational, unconfirmed) suggests the template FLOW button takes `text` plus one of `flow_id`,
`flow_name` or `flow_json`, with `flow_action` defaulting to `navigate`, a `navigate_screen` defaulting to
`FIRST_ENTRY_SCREEN` (spelled "nagivate_screen" in the source it paraphrases), `flow_message_version` of `"3"`
for interactive messages, invalid screens rejected at send time with an API error, and a changelog entry
allowing a Flow button alongside other button types in one message. **None of this was confirmed against a page
in the register and Lynomia must not publish it as fact.** It is a research lead for Agent 028 or a Phase 5
re-check, nothing more.

### 2.9 Carousel templates — media card carousels

From S13. Carousel cards "are only available for marketing template messages."

- Cards: **minimum 2, maximum 10**, fixed at creation. "An approved template can only be used to send the same
  number of cards."
- "All cards defined on a template must have the same components." Every card needs an image or video header
  (`format`: `image` or `video`). Card body is optional, but if any card has body text, all must. Buttons are
  optional, **up to two per card**, drawn from `quick_reply`, `phone_number` and `url`, and a mix is allowed.
- Creation: a `carousel` component containing a `cards` array, each card with its own `components`; each card
  header needs a `header_handle` from the Resumable Upload API. Media is automatically cropped to a wide ratio
  based on the user's device.
- Send: the `carousel` component's `cards` array, each card with `card_index` ("zero-indexed order in which card
  should appear", `0` first), a `header` component whose `image`/`video` parameter references the asset by
  **`id`** (a `MESSAGE_HEADER_ASSET_ID` from `POST /<BUSINESS_PHONE_NUMBER_ID>/media`), an optional `body`
  component, and buttons with `sub_type` `quick_reply` (optional `payload` parameter) or `url` (a `text`
  parameter filling the URL variable). Button `index` is zero-indexed, and "if buttons use variables, the type
  and order must match the template definition."

S13 states **no availability label** — not GA, not beta, not limited. It only constrains the feature to
marketing templates. S13 also documents a **card body limit of 160 characters**, distinct from the 1024-character
message body.

Product carousels (`…/catalogs/product-card-carousel-template-messages`) exist in the S3 index and were **not
checked**.

### 2.10 Catalog and multi-product message templates

From S14 and S15. Both require inventory in an e-commerce catalog **connected to the WhatsApp Business account**,
and both require template `status` of `APPROVED` before sending (API-created templates start `PENDING`).

**Catalog templates (S14).** Category in the examples is `MARKETING`. Components: BODY (variables supported,
example required if variables used), optional FOOTER, BUTTONS with one `{"type": "CATALOG", "text": "View
catalog"}`. At send: a button component with **`sub_type: "CATALOG"` (uppercase on S14)**, `index: 0`, and
`parameters: [{"type": "action", "action": {"thumbnail_product_retailer_id": "<SKU>"}}]`. The
`thumbnail_product_retailer_id` is **optional** — it is the item SKU, labelled "Content ID" in Commerce Manager,
and its thumbnail becomes the header image; **if `parameters` is omitted, the first catalog item's image is
used.** S14 states no beta label, no country restriction, and no limit on catalog buttons per template.

**MPM templates (S15).** Category `MARKETING`. Required: exactly one HEADER (`format: TEXT`, `text` max 60,
supports one variable), one BODY (max 1024, multiple variables), one BUTTONS with `{"type": "MPM", "text":
"View items"}`; FOOTER optional. At send: include the header component only if the template has a header
variable, the body component only if it has body variables, and exactly one button component with
`sub_type: "mpm"`, `index: 0`, and `parameters: [{"type": "action", "action": {thumbnail_product_retailer_id,
sections: [{title, product_items: [{product_retailer_id}]}]}}]`.

Constraints: **max 10 sections**, **max 30 products**, section `title` max 24 characters with no Markdown
support, recipients must be on WhatsApp client **v2.22.24 or later**, and **MPM templates cannot be forwarded
to other customers**. When a customer submits a cart, a webhook arrives with `"type": "order"` containing
`order.catalog_id` and `product_items` (each with `product_retailer_id`, `quantity`, `item_price`, `currency`).

S15 contains a **self-contradiction**: its parameter table says the 30-product maximum applies "across all
sections", while a comment in its request syntax says "Add up to 30 product items per section." Recorded in §6.
Lynomia should document the stricter reading (30 total).

### 2.11 Coupon code templates

From S12. Creation: `{"type": "COPY_CODE", "example": "<code>"}` where `example` is **required, max 20
characters**, and is a stored sample — "It is not the code sent to users." Send: a button component with
`sub_type: "copy_code"`, a zero-indexed `index` (S12's own example uses `1` because a quick-reply button comes
first), and `parameters: [{"type": "coupon_code", "coupon_code": "<≤20 chars>"}]`.

Constraints: **not supported by the WhatsApp web client**; copy-code button text cannot be customised; one
copy-code button per template. S12 cleanly separates creation-only properties (header, body, quick-reply label,
copy-code example) from send-only properties (body parameter values, coupon code) — a distinction Lynomia's own
template UI should mirror. No beta label.

---

## 3. Error codes and failures

Every code below is quoted from a source row. **No code in this table was inferred.**

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 131053 | not stated | Mismatched MIME type (described as "a common error") | The declared type does not match the actual file | "Check that file extensions match the actual file type" | message not delivered | S8 |
| 131052 | not stated | not stated | Delivered in a **webhook** when a customer sends a media file larger than 100 MB | inbound only; nothing to send-side fix | their media is rejected | S8 |
| HTTP 404 | n/a | Not Found | A media **download** failed | Request a new media URL and retry; if that fails, renew the access token | missing media in agent view | S8 |
| `HANDSHAKE_ID_MISSING` | n/a | as written | SDK-level: no handshake id present | perform the handshake before sending | copy-code button instead of autofill | S10, S11 |
| `HANDSHAKE_ID_INVALID_FORMAT` | n/a | as written | SDK-level: malformed handshake id | fix the client integration | as above | S10, S11 |
| `HANDSHAKE_ID_MISMATCH` | n/a | as written | SDK-level: handshake id does not match the stored value | fix the client integration | as above | S10, S11 |

**Failures Meta describes without giving a code.** These matter more to a support desk than the table above,
and Lynomia must document them as symptoms, not codes:

| Failure | What Meta says | Source |
|---|---|---|
| Media `link` not publicly reachable | "your asset must be on a publicly accessible server or the message will fail to send" | S6 |
| Unencoded characters in a dynamic URL suffix | "Unencoded characters can cause send failures" | S5 |
| Buttons grouped incorrectly | "Incorrect grouping returns an API error" (code not stated) | S5 |
| Sending a non-`APPROVED` template | status must be `APPROVED`, not `PENDING` | S14, S15, S17 |
| Carousel button variable order mismatch | "the type and order must match the template definition" | S13 |
| Zero-tap terms not accepted | if `zero_tap_terms_accepted` is `false`, "the template is not created" | S11 |
| GIF header over 3.5 MB | "Larger files display as video messages" (degradation, not an error) | S5 |
| Carousel card count mismatch | an approved template "can only be used to send the same number of cards" | S13 |

**Not found anywhere in the register**: a documented error code for a wrong header format at send, a wrong
media type for a header, a carousel `card_index` out of range, a button `index` that does not exist in the
template, a coupon code over 20 characters, or an OTP over 15 characters. Agent 005 and Agent 011 own the
request-time error families; Lynomia's whatsapp-errors section must not invent codes for these.

---

## 4. Limits and numbers

Every row cites the page that states it. Nothing here is derived.

| Limit | Value | Source |
|---|---|---|
| Template name | 512 chars, lowercase alphanumeric + underscores | S4, S13, S15 |
| Header text | 60 chars, 1 parameter | S5, S15 |
| Body text | 1024 chars | S5, S14, S15 |
| Footer text | 60 chars | S5, S14, S15 |
| Button label (QUICK_REPLY / URL / PHONE_NUMBER) | 25 chars | S5, S13 |
| `phone_number` value | 20 chars, alphanumeric | S5, S13 |
| URL button `url` (incl. the variable) | 2000 chars, 1 variable at the end | S5, S13 |
| Buttons per template | 10 total across all types | S5 |
| URL buttons per template | 2 | S5 |
| PHONE_NUMBER buttons per template | 1 | S5 |
| COPY_CODE buttons per template | 1 | S5, S12 |
| COPY_CODE `example` / send `coupon_code` | 20 chars each | S5, S12 |
| Buttons before the "See all options" fold | more than 3 → 2 shown | S5 |
| Desktop viewing breaks at | 4+ buttons, or quick reply + another type | S5 |
| Carousel cards per template | min 2, max 10 | S13 |
| Carousel buttons per card | 2 | S13 |
| Carousel card body text | 160 chars | S13 |
| GIF header | MP4, up to 3.5 MB | S5 |
| MPM sections | 10 | S15 |
| MPM products | 30 (table: "across all sections"; syntax comment says per section) | S15 |
| MPM / list section `title` | 24 chars | S15, S2 |
| Minimum WhatsApp client for MPM | v2.22.24 | S15 |
| One-time password | max 15 chars, must appear twice in the payload | S10, S11 |
| `code_expiration_minutes` | min 1, max 90; button disables after 10 min if omitted | S9, S10, S11 |
| OTP handshake validity window | 10 minutes, or `code_expiration_minutes` if set | S10, S11 |
| `supported_apps` entries | up to 5 | S10, S11 |
| `package_name` | max 224 chars | S10, S11 |
| `signature_hash` | exactly 11 chars from `a-zA-Z0-9+/=` | S10, S11 |
| `autofill_text` / OTP button `text` | 25 chars each | S10, S11 |
| Template creation rate | 100 templates per hour per WABA | S4 |
| Templates per WABA | 250 (unverified portfolio) / 6,000 (verified portfolio with approved display name) | S4 |
| `/media` upload: image | 5 MB, 8-bit RGB/RGBA, `image/jpeg` or `image/png` | S8 |
| `/media` upload: video | 16 MB, H.264 + AAC, `video/mp4` or `video/3gpp` | S8 |
| `/media` upload: document | 100 MB, 8 listed MIME types | S8 |
| `/media` upload: audio | 16 MB | S8 |
| `/media` upload: sticker | 100 KB static / 500 KB animated, `image/webp` | S8 |
| Media id validity (API-uploaded) | 30 days | S8 |
| Media id validity (from webhooks) | 7 days | S8 |
| Uploaded file retention | 30 days unless deleted | S8 |
| Media URL validity | 5 minutes | S8 |

---

## 5. Version and deprecation notes

| Item | Version / date | Source |
|---|---|---|
| OTP `supported_apps`: top-level `package_name` / `signature_hash` on the button object | allowed on **v20.0 or older**, "not recommended", **support ends at v21.0** | S11 |
| `PendingIntent`-based OTP handshake | **deprecated 2026-10-15** (an extended deadline); the OTP Android SDK is the preferred path | S10, S11 |
| Keyboard suggestions enabled by default for all authentication templates | **effective 2026-06-15**, iOS 26 and later | S9, S10, S11 |
| Linked-device security for authentication templates | enabled by default, not configurable, **Cloud API only** | S9 |
| Example endpoint versions across pages | v19.0 (S14), v23.0 (S10, S13, S15), v25.0 (S13's example request) | S10, S13, S14, S15 |
| Documentation relocation | `/docs/whatsapp/**` → `/documentation/business-messaging/whatsapp/**`; S1 is now a redirect stub, S2 is a schema husk | S1, S2, S3 |
| `flow_message_version: "3"` | **observational, unconfirmed** — attributed to the Messages reference, not verified | O1 |

The version spread in Meta's own examples (v19.0 to v25.0 on pages all live on the same day) is itself worth
recording: a Lynomia article that pins a version will drift from Meta's examples, and an article that omits one
will not reproduce. Document the version Lynomia's code actually calls, sourced from the code, not from Meta's
samples. Agent 040 owns that fact.

---

## 6. Ambiguities and gaps

Stated plainly, not resolved by guessing.

1. **No documented formats or size limits for template header media.** S5, S6 and S7 all omit them. S8's table
   governs `/media` uploads and media messages. Whether a 6 MB JPEG is acceptable as a Resumable Upload
   template-creation asset is **not answerable from the register**. This is the single largest gap in scope.
2. **The Resumable Upload API page is not in S3's index** and was not located. Its endpoint, session protocol,
   the handle's format and lifetime, and its own size limits are all **not checked**. Someone must find it.
3. **`header_handle` vs "media ID".** S6 calls the Resumable Upload return value a "media ID" and then uses it
   as `header_handle`. S8's `/media` ids are a different thing with a different lifetime. Meta's wording
   conflates them.
4. **FLOW button creation is undocumented on the live page.** S17's "Sample request" for creating a template
   with a Flow is **empty**. `developers.facebook.com/docs/whatsapp/flows/reference/flowstemplates` **404s**.
   Field names, required-vs-optional, whether the Flow must be published, and FLOW-button counts are all
   unknown from normative sources.
5. **MPM product limit contradicts itself within one page** — 30 across all sections (table) vs 30 per section
   (syntax comment), S15.
6. **Casing is inconsistent across Meta's own pages.** `format` is `location` in S5's syntax and `LOCATION` in
   its example. `sub_type` is `"CATALOG"` on S14 but lowercase (`quick_reply`, `url`, `copy_code`, `mpm`,
   `flow`) everywhere else. `otp_type` is `COPY_CODE`/`ONE_TAP` on S9 and `one_tap`/`zero_tap` on S10/S11.
   Lynomia cannot document a single casing convention honestly; document the value per feature as Meta writes it.
7. **`index` type is inconsistent.** S10 and S13 note the syntax block shows an integer while the example
   request uses a string. Both presumably work; neither page says which is canonical.
8. **Template document header `filename`** is documented only on S7, the **beta Direct Send** page. Whether a
   Cloud API template document header accepts `filename` is **not stated**.
9. **No availability label on carousel, catalog, MPM or coupon templates.** Meta labels none of them GA, beta or
   limited. Absence of a beta label is not a GA statement. Per the brief's rule, Lynomia should describe these
   as "documented by Meta, availability not labelled" rather than asserting general availability.
10. **Not checked**: the Resumable Upload API, product-card carousel templates, single-product (SPM) templates,
    unified catalog templates, limited-time-offer templates, call-permission-request templates, booking-appointment
    templates, location-request templates, VOICE_CALL / calling buttons, APP buttons, payments templates (IN, BR,
    MX), template groups, time-to-live, and tap-target URL title override. All are in S3's index. Several are
    plainly relevant to Lynomia's commerce integrations and deserve a follow-up brief.

---

## 7. What Lynomia users would ask

These are the questions this surface actually produces for a support desk, each answerable from §2 of this
report.

1. "I uploaded the image when I created the template — why does every send need the image again?" The creation
   asset is a review sample (S4); the send asset is separate (S6). This is the most likely single ticket in the
   whole area.
2. "My template image works in the preview but the message fails." `link` points at a server that is not
   publicly reachable (S6). Lynomia should prefer uploading and sending `id`, as Meta recommends.
3. "The PDF arrives with a meaningless filename." Not answerable from Meta's docs for templates (§6.8).
4. "What size image can I use?" Lynomia must answer with the `/media` limits (5 MB, JPEG/PNG, 8-bit RGB/RGBA)
   and say plainly that Meta does not publish a creation-side header limit (§6.1).
5. "My customer says the buttons are missing on WhatsApp Web / desktop." Expected: 4+ buttons, or a quick reply
   mixed with another type, cannot be viewed on desktop (S5); coupon/copy-code templates are unsupported on web
   (S12).
6. "The template was rejected with a button error." Almost always the grouping rule: quick replies must be
   contiguous (S5).
7. "The URL button opens a broken link." Unencoded characters in the dynamic suffix (S5), or a variable placed
   somewhere other than the end of the URL.
8. "Our OTP autofill shows a copy-code button instead." One of the six eligibility checks failed, or the
   recipient is not on Android (S10, S11). The downgrade is silent and by design.
9. "Can we send an OTP to iPhone users with autofill?" Not via one-tap or zero-tap (Android only). From
   2026-06-15, iOS 26+ gets Keyboard suggestions with no integration (S9–S11).
10. "Can we change the carousel from 3 cards to 5?" No — the card count is fixed at approval; a new template is
    required (S13).
11. "Why can't the customer forward our product list?" MPM templates cannot be forwarded (S15).
12. "The catalog message shows the wrong product image." `thumbnail_product_retailer_id` was omitted, so the
    first catalog item's image was used (S14).
13. "How many templates can we create?" 100/hour, and 250 per WABA unverified vs 6,000 verified with an
    approved display name (S4) — which turns a template-limit ticket into a business-verification ticket.
14. "Media stopped loading in the agent view after a few minutes." Media URLs expire after 5 minutes; media ids
    from webhooks after 7 days, from the API after 30 (S8).
