# 01 — The Meta WhatsApp template contract, verified at v24.0 (October 2026)

Verified against Meta's **current** documentation at `developers.facebook.com/documentation/business-messaging/whatsapp/…`
and the Message Template API reference, not from this repository's earlier discovery notes. Where the older
`/docs/whatsapp/business-management-api/message-templates/` pages disagree, they are wrong: they render frozen at v23.0,
omit every edit and delete limitation, and print WhatsApp Manager display labels as if they were API values.

Sources are listed in §13. Anything this document could not establish is in §14 — those are the places where Meta
stays authoritative and its error is surfaced rather than a number being invented.

**Graph version in this repo:** `Whatsapp::FacebookApiClient::DEFAULT_API_VERSION = 'v24.0'`
(`app/services/whatsapp/facebook_api_client.rb:3`), overridable by the `WHATSAPP_API_VERSION` installation config
(seeded `v24.0`, `config/installation_config.yml:179-182`, `locked: false`). Base URL
`ENV['WHATSAPP_CLOUD_BASE_URL']`, default `https://graph.facebook.com`.

---

## 1. The five endpoints, and which node each lives on

| Operation | Verb + path | Node |
|---|---|---|
| Create | `POST /{WABA_ID}/message_templates` | WABA |
| List | `GET /{WABA_ID}/message_templates` | WABA |
| Delete | `DELETE /{WABA_ID}/message_templates` | WABA |
| Get one | `GET /{TEMPLATE_ID}` | template |
| Edit | `POST /{TEMPLATE_ID}` | template |

**There is no `DELETE /{TEMPLATE_ID}` and no `POST /{WABA_ID}/message_templates/{id}`.** Mixing the nodes up produces
confusing 400s rather than 404s. Create and delete are on the WABA; get and edit are on the template.

This repo currently performs list (paginated, probe, and config-check variants), get-by-name, create and delete-by-name
— all enumerated with file and line in `00-current-system.md §3`. It has never edited a template, never deleted by id,
and never read one by id.

---

## 2. Create — `POST /{WABA_ID}/message_templates`

**Required:** `name`, `language`, `category`, `components`.
**Optional and current:** `parameter_format`, `message_send_ttl_seconds`, `sub_category`, `product_set_id`,
`cta_url_link_tracking_opted_out`.

### Categories

`UTILITY` · `MARKETING` · `AUTHENTICATION`. Nothing else.

- The pre-2022 values (`ACCOUNT_UPDATE`, `ALERT_UPDATE`, `APPOINTMENT_UPDATE`, `AUTO_REPLY`, `ISSUE_RESOLUTION`,
  `PAYMENT_UPDATE`, `PERSONAL_FINANCE_UPDATE`, `RESERVATION_UPDATE`, `SHIPPING_UPDATE`, `TICKET_UPDATE`,
  `TRANSPORTATION_UPDATE`) are deprecated for v14.0+. They still come back on old templates — this repo's own factory
  stores `'category' => 'SHIPPING_UPDATE'` (`spec/factories/channel/channel_whatsapp.rb:9`) — so **parse them, never
  offer them**.
- **`allow_category_change` is gone.** Effective 2025-04-09 Meta no longer supports the property on create; the
  behaviour it enabled is now the default. It is still present in the v26 reference schema. **Do not send it.**
- **The category you submit may not be the category you get.** Meta can create a `UTILITY` submission as `MARKETING`.
  Persist `category` from the create **response**, never from the request, and expect later drift through
  `template_category_update`.
- `sub_category` accepts `ORDER_DETAILS` / `ORDER_STATUS` / `RICH_ORDER_STATUS` on create, but reads return
  `CUSTOM` as well — validating reads against the create enum would reject real templates.

### Name

- Max **512** characters; lowercase letters, digits and underscores only.
- **Names are not unique across languages**, and are unique per `(WABA, name, language)`: a duplicate returns
  `code 100`, subcode `2388024`, "Content in This Language Already Exists". Both statements in Meta's docs are true at
  once; the identity is the triple.

### Language

- A language-and-locale code, e.g. `en`, `en_US`, `ar`, `pt_BR`.
- **The separator is inconsistent between surfaces.** The template API uses `en_US`; the
  `message_template_status_update` and `message_template_quality_update` webhook samples use **`en-US`**, while
  `message_template_components_update` uses `en_US`. Normalise `-` → `_` before matching anything.

### Components

Component `type` on create/edit: `HEADER`, `BODY`, `FOOTER`, `BUTTONS`, plus the special forms `CAROUSEL`,
`LIMITED_TIME_OFFER`, `ALBUM`, `GREETING`, `CALL_PERMISSION_REQUEST`, `TAP_TARGET_CONFIGURATION`, `ATTACHMENT`.
P3 authors only `HEADER`, `BODY`, `FOOTER`, `BUTTONS` (§12).

- **HEADER** — at most one. `format`: `TEXT`, `IMAGE`, `VIDEO`, `DOCUMENT`, `LOCATION`, `GIF`, `COLLECTION`.
  A TEXT header carries `text` and supports **one** variable. A media header carries no text; its `example` is a
  `header_handle` (an uploaded media handle, not a URL).
- **BODY** — required, exactly one. `text`, with any number of variables.
- **FOOTER** — at most one. `text`, **no variables**.
- **BUTTONS** — at most one component, holding a `buttons` array.

### Character limits — verified verbatim from Meta's components page

| Element | Limit |
|---|---|
| Header `TEXT` | **60** |
| Body text | **1024** |
| Footer text | **60** |
| Button label `text` | **25** |
| Button `url` | **2000** |
| Button `phone_number` | **20** |
| COPY_CODE `example` / coupon code | **20** |
| Template `name` | **512** |

> **A stale limit in this repo.** `Whatsapp::PopulateTemplateParametersService:19-20` raises `ArgumentError` for a
> coupon code over **15** characters, and `Flows::Template::COPY_CODE_MAX = 15` mirrors it. Meta's limit is **20**
> (raised 2025-12-03). So Lynomia today refuses 16–20-character coupon codes that Meta accepts. The manager must
> validate against 20; raising the two send-path constants is a one-line change with a flow-validation blast radius,
> recorded here and decided in the implementation part rather than assumed.
>
> Also note `sanitize_parameter` truncates parameter **values** to 1000 characters
> (`populate_template_parameters_service.rb:135-140`) while `Flows::Variables::MAX_VALUE = 1024`, so a 1001–1024-char
> value passes flow publish validation and is silently truncated at send. That is a send-path defect, not a template
> contract one.

### Buttons

`type` accepted by **create/edit**: `QUICK_REPLY`, `URL`, `PHONE_NUMBER`, `COPY_CODE`, `OTP`, `FLOW`, `CATALOG`, `MPM`.
`type` values that come back on **reads and webhooks** are a wider set, adding `EXTENSION`, `ORDER_DETAILS`,
`POSTBACK`, `REMINDER`, `SEND_LOCATION`, `SPM`, `VOICE_CALL`.

| Type | Max per template | Fields | Notes |
|---|---|---|---|
| `QUICK_REPLY` | 10 | `text` | the label is sent back to you when tapped |
| `URL` | 2 | `text`, `url`, `example` when the URL has a variable | one variable, **appended to the end** of the URL |
| `PHONE_NUMBER` | 1 | `text`, `phone_number` | leading zeros after the country code are stripped |
| `COPY_CODE` | 1 | `example` (a **string**, not an array) | the code itself is supplied at send time |
| `OTP` | 1, authentication only | `otp_type`, optional `text`, `package_name`/`signature_hash` or `supported_apps` | see §5 |
| `FLOW`, `CATALOG`, `MPM` | — | provider-specific | not authored by P3 (§12) |

**Total: at most 10 buttons.**

**Grouping is positional, not just a count.** Meta: "If using quick reply buttons with other buttons, buttons must be
organized into two groups: quick reply buttons and non-quick reply buttons. If grouped incorrectly, the API will
return an error indicating an invalid combination."

- Valid: `[QR, QR]` · `[QR, QR, URL, PHONE]` · `[URL, PHONE, QR, QR]`
- **Invalid:** `[QR, URL, QR]` · `[URL, QR, URL]`

So a button editor must keep quick replies contiguous, not merely respect per-type maxima.

Rendering facts worth surfacing in the builder, not blocking on: a template with **4 or more buttons**, or a quick
reply mixed with another type, cannot be viewed on WhatsApp desktop clients; with more than three buttons, two appear
in the message and the rest move behind a list.

### Variables, `parameter_format`, and the example keys

- Placeholders are `{{…}}`.
- `parameter_format` is **one value for the whole template**: `NAMED` or `POSITIONAL`. Reads return uppercase; create
  accepts lowercase. **Default is `POSITIONAL` when the field is omitted.**
- `NAMED`: `{{first_name}}` — unique, lowercase letters and underscores.
- `POSITIONAL`: `{{1}}`, `{{2}}`, … **starting at 1**, sequential, and the example values are given in placeholder
  order.
- Do not mix the two in one template.

**`example` is required at create for every component that has a variable**, and the key depends on component and
format:

| Component | `POSITIONAL` key | `NAMED` key | Shape |
|---|---|---|---|
| HEADER TEXT | `header_text` | `header_text_named_params` | positional: `["Pablo"]` (flat) |
| HEADER media | `header_handle` | `header_handle` | `["4::aW..."]` |
| BODY | `body_text` | `body_text_named_params` | positional: `[["Pablo","860198-230921"]]` — **nested** |
| URL button | `example` | `example` | `["summer2023"]` |
| COPY_CODE button | `example` | `example` | `"250FF"` — a bare string |

> `body_text` is an **array of arrays**; `header_text` is a flat array. The components page's abstract syntax block
> shows `body_text` with one level, but the reference schema and every real sample use two. Get this wrong and create
> fails with an unhelpful error.

**Placement rules Meta rejects on** (status `REJECTED`, `rejected_reason: INVALID_FORMAT`), each costing a review
cycle, so they are validated before submit:

- the text **cannot start or end with a parameter** — no dangling placeholders;
- two adjacent parameters (`{{1}}{{2}}`) are rejected — Meta's own returned text is "Your template has parameters
  placed next to each other (like {{1}}{{2}}) without text or punctuation between them";
- placeholders must be sequential (`{{1}}, {{2}}, {{5}}` is rejected);
- unmatched braces are rejected;
- parameters must not contain `#`, `$`, `%`;
- too many parameters relative to the message length is rejected.

**At send time** the two formats differ: named sends
`{"type":"text","parameter_name":"first_name","text":"Jessica"}`; positional sends `{"type":"text","text":"Jessica"}`
in order. URL-button parameter values must be percent-encoded at send time.

### Casing

Create and edit accept lowercase (`"category":"utility"`, `"type":"header"`, `?status=approved`); reads and webhooks
return uppercase. **Compare case-insensitively in both directions** — which is already how every comparison in this
repo works (`00-current-system.md §5`).

---

## 3. List — `GET /{WABA_ID}/message_templates`

- Fields available: `id`, `name`, `language`, `status`, `category`, `components`, `rejected_reason`, `quality_score`,
  `correct_category`, `previous_category`, `sub_category`, `parameter_format`, `message_send_ttl_seconds`,
  `library_template_name`, `cta_url_link_tracking_opted_out`, `product_set_id`, `health_status`, `last_updated_time`,
  `source`.
- `summary` carries `message_template_limit` and `message_template_count`. **Read them; do not hard-code 250 or
  6000** — the higher allowance depends on portfolio verification *and* an approved display name on at least one
  number, neither of which is inferable locally.
- **v24.0 pagination:** an invalid `before`/`after` cursor returns error `131059`, and the documented remedy is to
  retry **without** cursors, which regenerates them. This error did not exist before v24.0. The repo's existing loop
  (`whatsapp_cloud_service.rb:47-62`) breaks on a blank `after` but has no such retry.
- `health_status: { can_send_message }` is a **direct sendability signal** and is not the same question as `status`
  (§7).

---

## 4. Status

The authoritative enum the API returns (`WhatsAppBusinessHSMStatus`):

```
APPROVED  ARCHIVED  DELETED  DISABLED  IN_APPEAL
LIMIT_EXCEEDED  PAUSED  PENDING  PENDING_DELETION  REJECTED
```

**Only `APPROVED` can be sent.**

- **`IN_REVIEW` and `APPEAL_REQUESTED` are not API values** — they are WhatsApp Manager display labels that the frozen
  v23 doc page prints. Do not code against them.
- **The webhook `event` enum is a superset of `status`.** It adds `FLAGGED`, `LOCKED`, `REINSTATED`, `UNARCHIVED`
  (§8). Writing a webhook `event` straight into a status field stores values the API never returns.

**`rejected_reason`** (`WhatsAppBusinessHSMRejectionReason`): `ABUSIVE_CONTENT`, `INCORRECT_CATEGORY`,
`INVALID_FORMAT`, `NONE`, `PROMOTIONAL`, `SCAM`, `TAG_CONTENT_MISMATCH`, and `CATEGORY_NOT_AVAILABLE` which is
**deprecated** — keep it in the parse allowlist for historical records only.

**Quality** — `quality_score: { score: GREEN|YELLOW|RED|UNKNOWN, reason, reasons[], date }`. `UNKNOWN` means no
feedback yet, not an error.

**Pausing** is automatic on `RED`: 1st instance 3 hours, 2nd 6 hours, 3rd disabled. Ordinary quality pauses expire by
themselves. **Pauses caused by Template Pacing do not** — they need `POST /{template_id}/unpause` or WhatsApp Manager,
so a UI that only says "wait for it to unpause" strands the user.

**Auto-archival:** 12 months without activity → `ARCHIVED`, then hard-deleted after 28 days, with no opt-out.
Activity means creating, editing, sending, appealing or unarchiving. A seldom-used campaign template can therefore
disappear, which is a thing the manager should make visible.

---

## 5. Authentication templates — and why P3 does not author them

- **The body text is fixed and not author-supplied.** Meta: authentication templates consist of fixed,
  non-customisable preset text, localised per language. The BODY component carries only
  `add_security_recommendation`; the FOOTER carries only `code_expiration_minutes`. A generic builder that always
  emits `{"type":"body","text":…}` fails for `category: authentication`.
- An OTP button is **required** — the extension for legacy authentication templates without one ended 2024-04-01.
- `ONE_TAP` and `ZERO_TAP` need an Android `package_name` and `signature_hash` (or `supported_apps`), which Lynomia
  has no way to collect and no reason to.
- **OTP buttons come back as `URL`.** You submit `type: OTP`; Meta stores `URL`. A naive round-trip of a read into an
  edit therefore changes the template.
- `Flows::Template.sendable?` already excludes `authentication` (`custom/app/services/flows/template.rb:32`), as does
  `isSendableTemplate` on the client, so these templates are outside every Lynomia send path already.

**Decision: P3 lists, previews and mirrors authentication templates, and does not offer to create or edit them.**
That is a contract reason, not a scope cut — the fields Meta requires are ones this product cannot supply.

---

## 6. Edit — `POST /{TEMPLATE_ID}`

Every rule here decides what the UI may offer (PART 8: do not show Edit when the API prohibits it).

- **Editable only in `APPROVED`, `REJECTED` or `PAUSED`.** Not `PENDING`, `IN_APPEAL`, `DISABLED`, `ARCHIVED`,
  `DELETED`, `PENDING_DELETION`, `LIMIT_EXCEEDED`.
- **Editable fields: `category`, `components`, `message_send_ttl_seconds`.** Never `name`, never `language`.
  The reference also permits `parameter_format`, `sub_category`, `cta_url_link_tracking_opted_out`, `display_format`,
  `is_primary_device_delivery_only`.
- **The category of an `APPROVED` template cannot be changed** — so the category field is editable only while the
  template is `REJECTED` or `PAUSED`.
- **There are no partial component edits.** Meta replaces **all** components with those in the request. An editor that
  changes only the body must still resubmit header, footer, buttons **and every `example` value**, or they vanish.
  This is the single largest correctness trap in the whole edit path.
- **Quotas:** an approved template may be edited **10 times per 30 days and once per 24 hours**. Rejected and paused
  templates are unlimited. **No API field reports the remaining count.**
- **An edit of an approved or paused template re-enters review** and is auto-re-approved unless it fails review.
- **The response is only `{"success": true}`** — no status, no id. Never optimistically mark a template approved after
  an edit; re-read it or wait for the webhook.
- Editing a `REJECTED` template is the API's resubmission path. Appeals (which require a sample) are WhatsApp
  Manager-only and produce `IN_APPEAL`.

**Decision on the invisible quota:** Lynomia does not keep a private edit counter. It warns before editing an approved
template ("WhatsApp allows one edit per 24 hours and ten per 30 days, and the template re-enters review") and maps
Meta's refusal to a clear message if the quota is already spent. Meta is authoritative; a local counter would be a
second truth that drifts, and it would need a column this phase is not entitled to add.

---

## 7. Delete — `DELETE /{WABA_ID}/message_templates`

Three shapes, and only one of them is safe as a per-row action:

| Parameters | Effect |
|---|---|
| `?name=order_confirmation` | **deletes every language variant of that name** |
| `?hsm_id=<id>&name=<name>` | deletes only the template with that id — **the documented shape requires the name alongside the id** |
| `?hsm_ids=[id,id,…]` | up to 100; cannot be combined with `name` or `hsm_id`; **if any id is invalid the whole request fails and nothing is deleted** |

- Response `{"success": true}`. Deleting a name that does not exist is an error.
- **A template that has been sent but not yet delivered goes to `PENDING_DELETION`**, and WhatsApp keeps trying to
  deliver for 30 days.
- **After deleting an approved template, its name cannot be reused for 30 days.** This is why
  `CsatTemplateNameService`'s versioned names exist (`00-current-system.md §9`), and why Duplicate must generate a
  genuinely new name rather than reusing one.
- **A `DISABLED` template cannot be deleted.**
- `PENDING_DELETION` as a webhook *event* means something narrower: deleted via WhatsApp Manager.

**Decision: the manager deletes with `hsm_id` + `name`, never with `name` alone.** The name form is correct for CSAT,
whose templates are one per name, and wrong as a default anywhere else. A delete is confirmed with its consequences
stated, including the 30-day name lockout.

---

## 8. Webhooks

### Delivery — the rule that shapes the whole design

From Meta's webhook-overrides page, verbatim:

> "Template webhooks (message_template_status_update, message_template_quality_update,
> message_template_components_update, template_category_update) and account-level webhooks (account_update,
> account_review_update, account_alerts) do not support callback overrides."

> "Meta always delivers these webhooks to your app's default callback URL."

Fields that *do* support an override: `messages`, `message_echoes`, `calls`, `consumer_profile`,
`messaging_handovers`, the four `group_*` fields, `smb_message_echoes`, `smb_app_state_sync`, `history`,
`account_settings_update`. For those, delivery priority is phone-number override → WABA override → the app's default
callback URL.

Lynomia registers only a **phone-level** override and has only phone-scoped routes, so template webhooks cannot reach
it today even if subscribed. `03-sync-and-lifecycle.md §4` is the design that follows from this.

### `message_template_status_update`

```json
{
  "object": "whatsapp_business_account",
  "entry": [{
    "id": "102290129340398",                      // the WABA id, as a STRING — the only tenant key present
    "time": 1751247548,
    "changes": [{
      "field": "message_template_status_update",
      "value": {
        "event": "APPROVED",
        "message_template_id": 1689556908129832,   // an INTEGER here; a numeric STRING in API responses
        "message_template_name": "order_confirmation",
        "message_template_language": "en-US",      // HYPHEN here; underscore in the API
        "reason": "NONE",
        "message_template_category": "UTILITY",
        "disable_info":   { "disable_date": "…" },                 // only when disabled
        "other_info":     { "title": "…", "description": "…" },    // only when locked/unlocked/paused
        "rejection_info": { "reason": "…", "recommendation": "…" } // only when REJECTED with INVALID_FORMAT
      }
    }]
  }]
}
```

- **`event` values:** `APPROVED`, `REJECTED`, `DISABLED`, `PAUSED`, `ARCHIVED`, `UNARCHIVED`, `DELETED`,
  `PENDING_DELETION`, `FLAGGED`, `LOCKED`, `REINSTATED`, `LIMIT_EXCEEDED`, `IN_APPEAL`, `PENDING`.
  **`FLAGGED`, `LOCKED`, `REINSTATED` and `UNARCHIVED` are not `status` values** — they are events about a template
  whose status may not have changed.
- `other_info.title` enum: `FIRST_PAUSE`, `SECOND_PAUSE`, `RATE_LIMITING_PAUSE`, `UNPAUSE`, `DISABLED`.
- `rejection_info.reason` and `.recommendation` are the human-readable text to show a user, and the only place Meta
  explains a rejection in words.
- **There is no phone number anywhere in the payload.** Tenant resolution is by `entry[].id` → WABA → channels.

### The other three template fields

- **`message_template_quality_update`** — `previous_quality_score`, `new_quality_score`, `message_template_id`,
  `_name`, `_language`.
- **`message_template_components_update`** — a **flattened** shape (`message_template_title`, `_element`, `_footer`,
  `_buttons` with `message_template_button_*` keys), not a `components` array. Useful as a cache-invalidation
  trigger; do not feed it to a component parser.
- **`template_category_update`** — note the missing `message_` prefix. It has **two different payload shapes on the
  same field**: advance notice carries `correct_category` + `category_update_timestamp` + `new_category` (which is the
  *current* category), and the completion event carries `previous_category` + `new_category` (the real new one).
  Reading `new_category` without checking which shape arrived gets it backwards.

### Subscription

The fields are declared WABA-wide on `POST /{WABA_ID}/subscribed_apps`. This repo sends
`%w[messages smb_message_echoes]` (+`calls`) and **resends the full list on every subscribe**, deliberately, because
Meta otherwise resets to defaults (`facebook_api_client.rb:8-9`, `webhook_setup_service.rb:84-89`). So
`message_template_status_update` must be added to that array — not subscribed by a separate call, which would
overwrite the existing fields.

---

## 9. Rate limits and counts

- Template count and allowance come from the list endpoint's `summary` (§3), never from a constant.
- Edit quotas are in §6 and are not reported by any field.
- Create/delete rate limits are not published as numbers Lynomia can enforce; Meta's error is surfaced.

---

## 10. Deprecated or removed — what an older implementation still gets wrong

1. `allow_category_change` — unsupported since 2025-04-09, still in the v26 schema. Do not send it.
2. The pre-2022 category values — parse, never offer.
3. The `hsm` **message type** — deprecated with v2.39; the `hsm_id`/`hsm_ids` *delete parameters* are vestigial names
   and are still current.
4. `error_subcode` — not included in v16.0+ error responses and "should not be relied upon"; use `code` and `details`.
   (The duplicate-name case still documents subcode `2388024`.)
5. `rejected_reason: CATEGORY_NOT_AVAILABLE` — deprecated.
6. Authentication templates without an OTP button — ended 2024-04-01.
7. Conversation-based pricing — deprecated; per-message pricing is current, with `category` as the input.
8. On-Premises `/v1/configs/...` template endpoints — a different, sunsetting product.
9. `/docs/whatsapp/business-management-api/message-templates/*` — frozen at v23.0 and missing every edit/delete rule.
10. A pre-v24 cursor loop — will not know to retry without cursors on error `131059`.

---

## 11. What this repo must stop assuming

| Earlier assumption | The verified contract |
|---|---|
| "delete by `hsm_id`" | the documented shape is `hsm_id` **plus** `name` |
| "there is an undocumented daily edit limit" | it is documented: 10 per 30 days, 1 per 24 hours, approved only |
| "character limits could not be established" | they are published and are in §2; the repo's coupon limit of 15 is stale against Meta's 20 |
| "the webhook `event` is the new status" | `event` is a superset; four of its values are not statuses |
| "`message_template_id` can be compared as a number" | integer in webhooks, numeric string in API reads; compare as strings |
| "language codes match between surfaces" | `en_US` in the API, `en-US` in two of the webhooks |
| "a name-scoped delete removes one template" | it removes every language |
| "status answers *can I send this?*" | `health_status.can_send_message` and pacing (`held_for_quality_assessment`) also decide |

---

## 12. What P3 deliberately does not implement, and the contract reason

| Not implemented | Reason in the contract |
|---|---|
| Authentication / OTP template authoring | the body is preset, and ONE_TAP/ZERO_TAP need an Android package name and signature hash (§5) |
| `CAROUSEL`, `LIMITED_TIME_OFFER`, `ALBUM`, `CATALOG`, `MPM`, `SPM`, `FLOW`, `VOICE_CALL`, `CALL_PERMISSION_REQUEST` components and buttons | `Flows::Template::UNSUPPORTED_COMPONENTS` and `isSendableTemplate` already exclude the interactive ones from every Lynomia send path, so authoring them would create templates the product cannot send |
| `LOCATION` headers | same: excluded from every send path today |
| `allow_category_change` | unsupported since 2025-04-09 (§10) |
| A TTL control | `message_send_ttl_seconds` is optional, defaults sensibly, and nothing in Lynomia reads it; it is recorded from Meta, not edited |
| Archive / unarchive | no endpoint path is documented (§14) |
| Appeals | WhatsApp Manager only; the API has no appeal call |
| `POST /{template_id}/unpause` | in scope only as a message in the UI for a pacing pause, since a quality pause clears itself; a control is not added without a verified need |
| A local edit-quota counter | no API field reports it, and a private counter would drift (§6) |
| Bulk delete via `hsm_ids` | all-or-nothing semantics make partial failure invisible; per-id deletes are used |

---

## 13. Sources

1. Message Template API reference — `WhatsAppBusinessHSM*` enums, create/edit/list/delete parameters, `Example` schema.
2. `…/whatsapp/templates/overview/` — placeholders, `parameter_format`, naming, categories.
3. `…/whatsapp/templates/components/` — component types, formats, **character limits**, button types and maxima,
   grouping rule.
4. `…/whatsapp/templates/template-management/` — edit limitations and quotas, delete shapes, name lockout.
5. `…/whatsapp/templates/template-review/` — rejection reasons and parameter-placement rules.
6. `…/whatsapp/templates/template-quality/`, `…/template-pausing/`, `…/template-pacing/`,
   `…/portfolio-pacing/`, `…/template-archival/`.
7. `…/whatsapp/templates/authentication-templates/`.
8. `…/whatsapp/webhooks/override/` — the delivery rule in §8.
9. `…/whatsapp/webhooks/reference/message_template_status_update` and the three sibling field references.
10. WhatsApp changelog — `allow_category_change` removal (2025-04-09), coupon-code limit 15→20 (2025-12-03),
    portfolio pacing (2025-12-08), category deprecations (2022-05-19).

---

## 14. What could not be established, where Meta stays authoritative

1. **Archive / unarchive endpoint paths.** The management and archival pages describe the behaviour and say it can be
   done "in bulk using the API", but no page gives a path or body. Not implemented (§12).
2. **Whether `FREE_SERVICE` is settable at create.** It is in the v26 `WhatsAppBusinessHSMTag` enum and appears in no
   guide. Treated as not self-service.
3. **Create and delete rate limits as enforceable numbers.** Not published; Meta's error is mapped.
4. **The exact `components` payload for every special component type** (carousel cards, limited-time offer). Out of
   scope for P3 (§12), so not pursued.
5. **Whether the Meta App Dashboard default callback URL is configured for this installation**, which is the
   precondition for any template webhook arriving. That is Meta-side configuration outside this repository; the design
   does not depend on it (`03-sync-and-lifecycle.md §4.4`).
