---
agent: 011
scope: Template sending — request shape, parameter supply (positional vs named), parameter mismatch failures, language resolution, non-APPROVED/PAUSED/DISABLED sends, the 132xxx family, and whether each failure is synchronous or webhook-delivered
confidence: high
sources_normative: 12
sources_observational: 0
---

# Agent 011 — Sending a template message, and everything that goes wrong doing it

## 1. Source register

Every claim below references a row here by `R<n>`. All rows are `developers.facebook.com`; no blog,
Stack Overflow or community source was used, so there are no observational rows.

| Row | Source URL | Page title | Product | API/version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| R1 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/` | Error Codes | WhatsApp Cloud API | States `error_subcode` "Will not be returned in v16.0+ responses"; a curl example uses `v25.0` | 2026-10-13 | normative |
| R2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/overview` (+ `.md`) | Template fundamentals / Overview | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/components` (+ `.md`) | Components | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R4 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/supported-languages` | Supported languages | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R5 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/send-messages` | Send messages | WhatsApp Cloud API | curl example uses `graph.facebook.com/v25.0` | 2026-10-13 | normative |
| R6 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/status.md` | status (messages webhook reference) | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-pausing.md` | Pausing | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R8 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/direct-send/api-reference.md` | API reference (Direct Send) | WhatsApp Direct Send | none stated | 2026-10-13 | normative |
| R9 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/direct-send/send-utility-and-authentication-messages.md` | Send utility and authentication messages | WhatsApp Direct Send | none stated | 2026-10-13 | normative |
| R10 | `https://developers.facebook.com/docs/graph-api/changelog` | Graph API Changelog | Graph API | v26.0 latest, introduced 2026-07-29 | 2026-10-13 | normative |
| R11 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/llms.txt` | WhatsApp documentation index | WhatsApp Cloud API | n/a (index only) | 2026-10-13 | normative (index) |
| R12 | `https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-message-templates/` | (redirect notice) | WhatsApp Cloud API | n/a | 2026-10-13 | normative (redirect only) |

Two notes on source hygiene. First, Meta has **moved the WhatsApp documentation** from
`/docs/whatsapp/cloud-api/**` to `/documentation/business-messaging/whatsapp/**`. R12 is now only a stub reading
"This page has moved. See Template fundamentals for information about template messages." The error-codes page
(R1) is the one significant page still served from the old `/docs/` path. Any Lynomia article or code comment
that links the old guide paths is already pointing at a redirect stub.

Second, `.../direct-send/send-sample-payloads.md` — advertised by Meta's own index (R11) — returned
**Page Not Found**. Meta's index references a page that does not resolve. That is why the parameter-type
enumeration in §6 is recorded as *not stated* rather than filled in.

## 2. The rules

### 2.1 The send request

A template message is sent through the ordinary message-send endpoint, not a template-specific one (R5):

```
POST /<WHATSAPP_BUSINESS_PHONE_NUMBER_ID>/messages
```

R5 gives the path without a version placeholder; its curl example uses the versioned host
`https://graph.facebook.com/v25.0/106540352242922/messages`. The body is the standard envelope —
`messaging_product`, `recipient_type`, `to`, `type` — with `type` set to `template` and a sibling object named
after the type. R2 gives this complete send payload:

```json
{
  "messaging_product": "whatsapp",
  "recipient_type": "individual",
  "to": "+16505551234",
  "type": "template",
  "template": {
    "name": "order_confirmation",
    "language": { "code": "en_US" },
    "components": [
      { "type": "body",
        "parameters": [
          { "type": "text", "text": "Jessica" },
          { "type": "text", "text": "SKBUP2-4CPIG9" }
        ] }
    ]
  }
}
```

The `language` object on every current page carries **only `code`** (R2, R4). No page read for this report
contains a `policy` field, a `"deterministic"` value, or any other language-resolution control. I am not
asserting that `language.policy` has been removed — only that it is **not stated** on the current pages, and
Lynomia must not rely on it without a page that documents it.

The success response contains a `messages` array with `id`, and R5 states that `message_status` "is only
included in responses when sending a template message" — so that property is template-specific and relates to
pacing. R5 is explicit that a success response is not a delivery guarantee: "it does not indicate successful
delivery of your message." Undeliverable messages "are retried until their time-to-live expires" and are then
dropped; if no `delivered` status arrives, R5 says to "assume the message was dropped."

### 2.2 How parameters are supplied: positional versus named

The format is fixed **at template creation**, not at send time (R2):

- "Upon template creation, if a string includes one or more parameters, you can specify their format — either
  `named` or `positional` — and you must include an example value for each parameter."
- "If you do not specify a format, the template uses `positional` format by default."
- Positional: "Positional parameters must be ordered array index numbers, starting from 1, wrapped in double
  curly brackets." Send values "must appear in the order in which their corresponding placeholders appear in
  the component text string."
- Named: "Parameters using the named format must be unique, single strings, composed of lowercase characters
  and underscores, wrapped in double curly brackets." For these, send values "can appear in any order."

Named sends add `parameter_name` to each parameter object (R2):

```json
"parameters": [
  { "type": "text", "parameter_name": "first_name",   "text": "Jessica" },
  { "type": "text", "parameter_name": "order_number", "text": "SKBUP2-4CPIG9" }
]
```

This is the operationally important asymmetry: **for a positional template, array order is semantically
load-bearing and silently wrong if shuffled; for a named template, order is irrelevant but `parameter_name`
must match the creation-time name exactly.** Creation uses different keys again — R3 shows `body_text` /
`header_text_named_params` / `"param_name"` on the create side versus `parameter_name` on the send side. A
Lynomia implementation that reuses one key name across both sides will be wrong on one of them.

**Whether named and positional may be mixed within one template is not stated** on R2 or R3. Record as
ambiguous (§6).

### 2.3 Components: header, body, buttons

R2 and R3 together give component `type` values `header`, `body` and `button`, each with a `parameters` array.
On the send side the pages read show:

- header: R3's only send-side header example is `"type": "header"` with a parameter of `"type": "location"`.
  Media headers are created with `header_handle`; the send-side media parameter shape is **not** on these
  pages (agent 012 owns media headers).
- body: positional and named text parameters, as above.
- button: R3's send-side example is `"type": "button"`, `"sub_type": "url"`, `"index": "0"`. Note `index` is a
  **string** in Meta's example, not an integer. R3 says only that "you can use the index property to designate
  the order in which buttons appear in the template message" and gives no allowed-value list. The URL button
  example carries `"parameter_name": "customer_name"`, confirming named parameters reach buttons too.

The full enumeration of button `sub_type` values and of parameter `type` values (`currency`, `date_time`,
`image`, `document`, `video`, `payload`, `coupon_code`) was **not found** on any page read. The page Meta's own
index points to for sample payloads is a 404 (§1). Not stated — do not fill this in from memory.

### 2.4 Status gate: only APPROVED sends

R2 is unambiguous: "Templates must have a status of `APPROVED` before they can be sent in template messages."
And: "If it is rejected, or if its status changes to any other value, it cannot be sent in template messages."

R2's status glossary, quoted:

| Status | Meta's wording (R2) | Sendable? |
|---|---|---|
| `APPROVED` | "If your template is approved, its status is set to `APPROVED`" and "you can begin sending it in template messages." | yes |
| Rejected | "The template has been rejected during the review process or violates one or more policies." | no |
| In-Review | "Indicates that the template is still under review." | no |
| Paused | "The template has been paused due to recurring negative feedback from customers, or low read-rates. Message templates with this status cannot be sent to customers." | no |
| Disabled | "The template has been disabled due to recurring negative feedback from customers. Message templates with this status cannot be sent to customers." | no |

`PENDING` is not a status named on R2. Lynomia should not display it as a template state without a source.

### 2.5 Pausing and disabling, and how to recover

R7 is the normative page. A template reaching the lowest quality rating — "a status of Active - Low quality in
WhatsApp Manager, or a `quality_score` of RED via API" — "will automatically be paused for a period of time to
protect the quality rating of phone numbers that have used the template." The escalation ladder, verbatim:

- "1st Instance: Paused for 3 hours"
- "2nd Instance: Paused for 6 hours"
- "3rd Instance: Disabled"

Crucially for this report's central question, R7 states that while paused the template "can't be sent to
customers" and that **"the API will reject these attempts anyway."** That is Meta explicitly placing the
paused-template failure at request time.

Recovery differs by cause, which Lynomia must not flatten into one message:

- Quality pause: "A template will unpause on its own after satisfying the pause duration outlined above." On
  unpause, "The template's quality rating will also be reset to a value based on the most recent customer
  feedback the template has received."
- **Template Pacing pause: "templates paused during Template Pacing must be manually unpaused (API or
  WhatsApp Manager) before they can be used again."** The call is `POST /{whats_app_message_template_id}/unpause`.
  This one will not clear itself, so a business waiting for a timer waits forever.
- Edit path: "once you edit a message template and resubmit it for approval, its status will change to In
  Review" — which means editing a paused template makes it unsendable until re-approval, not immediately
  sendable.
- Disabled: "If an approved template has become disabled, you may also edit it and resubmit it for approval."
  Appeals "must include a sample." R7 does not state in so many words that a disabled template is rejected at
  send time; R2 states it cannot be sent, and code 132016 (§3) describes it as "permanently disabled."

R7 names the `message_template_status_update` webhook as the signal ("a `message_template_status_update`
webhook will be triggered"). It does **not** mention `message_template_quality_update`, although Meta's index
(R11) lists a page for that webhook. Lynomia should subscribe to status updates to keep local template state
truthful rather than discovering a pause from a send failure.

### 2.6 Language and locale resolution — there is no documented fallback

This is a negative finding, and it is firm. R4 lists the supported languages and codes ("Cloud API message
templates support the following languages and language codes") and R2 states "You must assign a template
language code upon template creation" and that "Template strings and variables are not translated by Meta, so
you are responsible for supplying strings."

Neither page describes **any** fallback, inheritance, or resolution behaviour: no language fallback, no
`policy` field, no automatic locale negotiation, and no statement of what happens when the requested language
has no approved template. R4 lists region-qualified and bare locales as **separate rows with separate codes**
(`en` and `en_US`; `ar` and `ar_EG`; also `en_GB`, `pt_BR`, `zh_CN`, `es_MX`), though it never explicitly says
these are non-interchangeable.

What *is* documented is the consequence: error **132001**, "The template does not exist in the specified
language or the template has not been approved" (R1). So the observable behaviour of an unapproved language is
a hard failure, not a fallback. Lynomia should treat `(template name, language code)` as the lookup key and
treat `en` and `en_US` as different templates.

### 2.7 Synchronous or webhook? Meta's own answer

R1's preamble settles this, and it is the single most quotable sentence for Lynomia's failure-message design:

> "Cloud API errors are returned either synchronously as a Graph API response, asynchronously via Webhook, or
> sometimes through both methods."

It follows with the instruction to "monitor both the Graph API response and the `messages` webhook for error
handling," and notes that if subscribed to the `messages` field "you will receive notification of errors as
they occur" "for supported asynchronous error types." R1 names the webhook locations as
`entry.changes.value.errors` and `entry.changes.value.messages.errors`.

R6 adds the third location that R1's list omits: inside a status object. `status` takes the values `sent`,
`delivered`, `read`, `played`, `failed`, with `failed` defined as "Indicates failure to send or deliver the
message to the WhatsApp user's device" and a "WhatsApp UI equivalent: Red error triangle." The `errors` array
there is annotated "only included if failure to send or deliver message" and has this shape (R6):

```json
"errors": [
  { "code": <ERROR_CODE>,
    "title": "<ERROR_TITLE>",
    "message": "<ERROR_MESSAGE>",
    "error_data": { "details": "<ERROR_DETAILS>" },
    "href": "<ERROR_CODES_URL>" }
]
```

R6 defines `title` as "Error code title. This value is the same as the `message` property value" and `message`
reciprocally. So **in a webhook, `title` and `message` are duplicates**, and the only text with incremental
information is `error_data.details`. In a synchronous Graph response the fields differ: R1 describes `message`
as a "Combination of the error code and its title" — i.e. the `(#132000) Title` form — and says "Code titles,
which do not have a dedicated property in API error response payloads, are included as part of the `message`
value," with the explicit warning to "build your app's error handling logic around `code` values" and to "not
rely on titles for your error handling logic."

**Therefore, precisely: the channel is per-error-type, Meta states it may be either or both, and Meta does not
label individual codes as synchronous or asynchronous.** The error-codes tables have no such column (§6). The
only per-case statement found is R7's "the API will reject these attempts anyway" for paused templates. Any
Lynomia claim that 132000 is "always a request-time error" would be unsourced — it must handle every template
code arriving on both paths, and key its user-facing copy off `code`.

One further precision that matters for Lynomia's copy: the second column of R1's "Other errors" table is headed
**`details`** (the full headers are "Code", "`details`", "Possible reasons and solutions"). The description
strings quoted in §3 are therefore the literal `error_data.details` values, usable verbatim in a Lynomia
failure message, while the "Possible reasons and solutions" column is Meta's remediation guidance and is not
transmitted in the payload.

## 3. Error codes and failures

Template send-time codes. Description text is Meta's `details` wording (R1) transcribed verbatim; `title` is
not separately published for these rows, so those cells read `not stated`.

| Code | Subcode | Title as Meta words it | What it means (Meta's `details`, R1) | What the business can do (Meta's words, R1) | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 132000 | not stated | not stated (R1 "Other errors" has no Title column) | "The number of variable parameter values included in the request did not match the number of variable parameters defined in the template." | "See our Templates document to learn about parameters and make sure the request includes values for all of the parameters required by the template." | Nothing, if rejected synchronously; red error triangle if surfaced as `failed` | R1 |
| 132001 | not stated | not stated | "The template does not exist in the specified language or the template has not been approved." | "Make sure your template has been approved and the template name and language locale are correct. See our Templates document to learn more about templates." | As above | R1 |
| 132005 | not stated | not stated | "Translated text is too long." | "Check the WhatsApp Manager to verify that your template has been translated." | As above | R1 |
| 132007 | not stated | not stated | "Template content violates a WhatsApp policy." | "See our Template review document to learn about possible reasons for the violation." | As above | R1 |
| 132012 | not stated | not stated | "Variable parameter values formatted incorrectly." | "The variable parameter values included in the request are not using the format specified in the template. See our Templates document to learn more about template parameters and formats." | As above | R1 |
| 132015 | not stated | not stated | "Template is paused due to low quality so it cannot be sent in a template message." | "Edit the template to improve its quality and try again once it is approved." | As above; R7 says the API rejects the attempt | R1, R7 |
| 132016 | not stated | not stated | "Template has been paused too many times due to low quality and is now permanently disabled." | "Create a new template with different content." | As above | R1, R7 |
| 132068 | not stated | not stated | "Flow is in blocked state." | "Correct the Flow" | As above | R1 |
| 132069 | not stated | not stated | "Flow is in throttled state and 10 messages using this flow were already sent in the last hour." | "Correct the Flow" | As above | R1 |

Adjacent codes a template send can realistically produce. These are not template-specific but are reached by
the same call, and Lynomia will see them mixed in with the above.

| Code | Title as Meta words it | Meta's description | Remediation (Meta's words) | Source |
|---|---|---|---|---|
| 100 | not stated | "The request included one or more unsupported or misspelled parameters." | "See the endpoint's reference to determine which parameters are supported and how they are spelled." | R1 |
| 131008 | not stated | "The request is missing a required parameter." | "See the endpoint's reference to determine which parameters are required." | R1 |
| 131009 | not stated | "One or more parameter values are invalid." | "See the endpoint's reference to determine which values are supported for each parameter" | R1 |
| 131047 | not stated | "More than 24 hours have passed since the recipient last replied to the sender number." | "Send the recipient a template message instead." | R1 |
| 131049 | not stated | "This message was not delivered to maintain healthy ecosystem engagement." | "wait at least 24 hours before resending the template message." | R1, R6 |
| 131050 | not stated | "This recipient has chosen to stop receiving marketing messages on WhatsApp from your business." | "Do not retry sending messages to this user as they will not be received." | R1 |
| 131063 | not stated | "marketing templates are currently disabled for your Cloud API configuration." | "To send this template, use the Marketing Messages API" or set `disable_marketing_messages_on_cloud_api` to `false` | R1 |
| 131064 | not stated | "Message failed to send because this account has reached its messaging limit due to template classification violations." | "Review your template classifications and ensure they are categorized correctly." | R1 |
| 135000 | not stated | "Message failed to send because of an unknown error with your request parameters." | "See the endpoint's reference to determine if you are querying the endpoint using the correct syntax." | R1 |
| 2388019 | "Message Template Limit Exceeded" | "You have exceeded the maximum number of message templates you can have for this WhatsApp business account." | "A WhatsApp Business account can have up to 250 message templates." | R1, "Send template errors" table |

Codes belonging to **other products**, kept separate so they are never mislabelled as Cloud API template
errors. R1 publishes these under "Marketing Messages API for WhatsApp error codes", whose table *does* have a
Message/Title column and an HTTP status column:

| Code | Title as Meta words it | Description | Remediation | HTTP | Source |
|---|---|---|---|---|---|
| 132018 | "(#132018) Template validation error" | "There's an issue with the parameters in your template." | "Review the errors, update the parameters as needed, and resend your message using a correctly configured template." | 400 Bad Request | R1 |
| 131055 | "(#131055) Method not allowed" | "Only marketing template messages are supported" | "Try sending again using a marketing template message." | 400 Bad Request | R1 |
| 134100 | "(#134100) Only marketing messages supported" | "You're only able to send marketing messages on this API." | "Only templates categorized as MARKETING are supported." | 400 Bad Request | R1 |
| 134101 | "(#134101) Your template is still syncing" | "When you send a message from a template, the template syncing process can take up to 10 minutes to complete" | "Wait 10 minutes and try again." | 400 Bad Request | R1 |
| 134102 | "(#134102) Template unavailable for use" | "Please check your eligibility status to ensure you are onboarded or contact Meta's customer support." | Check that `marketing_messages_lite_api_status` is `ONBOARDED` | 500 Internal Server Error | R1 |
| 132021 | not stated | "The `template_name` in `direct_send_config` conflicts with an existing template not created by Direct Send." | not stated | not stated | R8 |

### 3.1 The parameter-mismatch failure, stated exactly

The brief asks for the specific code behind the most common template failure in practice. It is **132000**, and
Meta's distinction between it and its neighbours is sharp and worth preserving in Lynomia's copy:

- **132000 — count mismatch.** The *number* of values sent differs from the number defined in the template.
  Meta's remedy is to include values for all required parameters.
- **132012 — format mismatch.** The right number of values, in the wrong *format* — "not using the format
  specified in the template."
- **132001 — identity mismatch.** The `(name, language)` pair does not resolve to an approved template.
- **132018 — parameter validation**, but only on the Marketing Messages API, not Cloud API.

So a Lynomia failure message must not say "parameter error" for all four. 132000 points the business at its own
variable *count*; 132012 at the *value shape*; 132001 at the template's *name, locale or approval state*.

A caution on 132001 that Lynomia's UX depends on: **the code conflates two distinct causes.** "The template
does not exist in the specified language" and "the template has not been approved" share one code. A user
seeing 132001 cannot be told which applies from the code alone. Lynomia must read `error_data.details` (which
is the same conflated sentence) or, better, query the template's status and language list before asserting a
cause. Guessing one of the two in the UI will be wrong a predictable fraction of the time.

Note also that 132015/132016 cover **paused** and **permanently disabled**, but R1 publishes no code whose
`details` names a *rejected* or *in-review* template. A send against a never-approved template is therefore
expected to surface as 132001, not as a status-specific code. That inference is mine, flagged in §6.

## 4. Limits and numbers

Only numbers a source states.

| Number | What it limits | Source |
|---|---|---|
| 1024 characters | Template body maximum; one body component per template | R3 |
| 60 characters | Text header maximum; also footer maximum ("60 characters maximum") | R3 |
| 1 parameter | Supported by a text header | R3 |
| 10 button components | "Templates can have a combination of up to 10 button components in total" | R3 |
| 10 / 2 / 1 / 1 | Quick-reply buttons / URL buttons / copy-code button / phone-number button per template | R3 |
| 25 characters | Button text maximum | R3 |
| 20 characters | Copy-code value maximum | R3 |
| 2000 characters | URL maximum; "Supports 1 variable, appended to the end of the URL string" | R3 |
| 3 buttons | "If a template has more than three buttons, two buttons appear in the delivered message" | R3 |
| 3 hours / 6 hours / disabled | 1st / 2nd / 3rd low-quality pause instance | R7 |
| 250 | Message templates per WhatsApp Business account (code 2388019) | R1 |
| 10 minutes | Marketing Messages API template sync wait (code 134101) | R1 |
| 10 messages/hour | Flow throttled state threshold (code 132069) | R1 |
| 24 hours | Customer service window referenced by 131047; resend wait for 131049 | R1 |

Positional parameters are "ordered array index numbers, starting from 1" (R3, R2) — the only numbering rule
stated. No maximum parameter count per body is stated on any page read; R1's creation-side code 2388293
("This template has too many variables for its length") implies a ratio limit but states no number.

## 5. Version and deprecation notes

- The latest Graph API version is **v26.0, introduced 2026-07-29**, "Available Until" TBD (R10). v25.0
  (2026-02-18) is available until 2028-07-29; v24.0 (2025-10-08) until 2028-02-18; v19.0 reached end of
  availability 2026-05-21 and v18.0 on 2026-01-26, so both are now expired.
- **`error_subcode` is deprecated**: R1 states "Deprecated. Will not be returned in v16.0+ responses." Lynomia
  must not key template-failure logic on subcodes. R1 also says to build handling "around error codes instead
  of subcodes or HTTP response status codes."
- Meta has relocated WhatsApp documentation to `/documentation/business-messaging/whatsapp/**`; the old
  `/docs/whatsapp/cloud-api/guides/**` guide paths are redirect stubs (R12), while the error-codes page (R1)
  still serves from `/docs/`. R6 shows Meta's own `href` in error payloads now pointing at
  `/documentation/business-messaging/whatsapp/support/error-codes`.
- R10 contains **no** entry mentioning WhatsApp message templates, template parameters, named parameters,
  template language, or template pausing. Template-level change history lives in a separate "WhatsApp Business
  Platform Changelog" linked from R10, which I did not fetch (§6).
- No page read states a minimum Graph API version for named parameters (`parameter_name`). Version context for
  that feature is **not stated**.

## 6. Ambiguities and gaps

Stated plainly, not resolved by guessing.

1. **Per-code failure channel is not published.** R1 says errors come synchronously, asynchronously, or both,
   and tells developers to monitor both — but no table column says which codes are which. Only paused
   templates have an explicit per-case statement ("the API will reject these attempts anyway", R7). Lynomia
   cannot derive a per-code answer from Meta's documentation today.
2. **Mixing named and positional parameters** in one template is neither permitted nor forbidden on R2 or R3.
3. **The send-side parameter `type` enumeration is unobtainable** from the pages read. `currency`, `date_time`,
   `image`, `document`, `video` and `payload` did not appear in any send payload I could reach; the page Meta's
   index advertises for sample payloads 404s. Agent 012 should treat this as an open item, not re-derive it.
4. **Button `sub_type` values and `index` bounds are not enumerated.** Only `sub_type: "url"` with
   `index: "0"` (a string) was found. R3 gives no allowed-value list.
5. **`language.policy` is absent** from current pages. Whether it was removed, is undocumented, or never
   applied to Cloud API cannot be determined from these sources.
6. **No code is published for sending a REJECTED or IN-REVIEW template.** My expectation that these surface as
   132001 is an **inference**, not a documented rule. It must be verified before Lynomia writes it into help
   copy.
7. **Disabled-template send behaviour at request time is not explicitly stated.** R2 says such templates
   "cannot be sent"; 132016 exists; but no page says the API rejects the call, as R7 does for paused.
8. Locales with and without a region (`en` vs `en_US`) are listed as separate rows but R4 "never explicitly
   says these are distinct."
9. The WhatsApp Business Platform Changelog, `message_template_quality_update`, Template Pacing and
   template categorization pages (all in R11) were not fetched — budget. They belong to agents 009, 010 and 012.

## 7. What Lynomia users would ask

These are the support questions this area generates, each answerable from §2–§3.

1. "I sent a template and got error 132000 — what do I fix?" Count your variables; the template defines a
   different number than you sent. Not a formatting problem.
2. "What is the difference between 132000 and 132012?" Count versus format. Different fixes.
3. "Error 132001 says the template does not exist — but I can see it in WhatsApp Manager." The name may be
   right and the *language* wrong, or it is not APPROVED. The code cannot tell you which; check both.
4. "Why does my Arabic template fail when the English one works?" `ar` and `ar_EG` are different templates, and
   there is no language fallback. Each locale needs its own approval.
5. "My template worked yesterday and fails today." Likely paused for low quality — 3 hours, then 6, then
   disabled. Check template status, not your code.
6. "The template says Paused. Do I wait or do something?" Depends on cause: a quality pause clears itself; a
   Template Pacing pause must be unpaused manually.
7. "Error 132016 — can I get my template back?" No. "Create a new template with different content."
8. "Lynomia reported success but the customer never received it." A 200 is not delivery (R5); watch for a
   `failed` status webhook, and if no `delivered` arrives before TTL, assume dropped.
9. "Where do I see the real reason a template failed?" `error_data.details` — in a webhook, `title` and
   `message` are duplicates of each other and carry no extra information.
10. "Why did my marketing template get refused with 131063?" Marketing templates are disabled for that Cloud
    API configuration; use the Marketing Messages API or flip `disable_marketing_messages_on_cloud_api`.
11. "I changed the template text and now nothing sends." Editing moves it to In-Review, which is not sendable.
12. "Can I reorder the values I send?" Only for named templates. For positional, order is the meaning.
