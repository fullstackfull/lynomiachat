---
agent: 005
scope: WhatsApp Cloud API message-send failures returned at request time — the complete published error corpus, by family, with retryability
confidence: high
sources_normative: 10
sources_observational: 1
---

## 1. Source register

| # | Source URL | Page title | Product | API / version context | Date checked | Normative? |
|---|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | Error Codes | WhatsApp Cloud API | Cloud API on Graph API; states `error_subcode` not returned in v16.0+; MM API codes 134100/134101/134102 from v23.0 | 2026-10-13 | normative |
| S2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/support/error-codes` | WhatsApp error codes | WhatsApp Business Platform (current canonical path) | same content as S1; same version statements | 2026-10-13 | normative |
| S3 | `https://developers.facebook.com/docs/graph-api/guides/error-handling` | Error Handling | Graph API | version-independent | 2026-10-13 | normative |
| S4 | `https://developers.facebook.com/docs/graph-api/overview/rate-limiting` | Rate Limiting | Graph API | notes Ads API v3.3-and-older behaviour for one header | 2026-10-13 | normative |
| S5 | `https://developers.facebook.com/docs/whatsapp/support` | WhatsApp support | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| S6 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/` | Onboard WhatsApp Business app users | WhatsApp Business Platform (Embedded Signup / Coexistence) | none stated | 2026-10-13 | normative |
| S7 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages` | Messages (endpoint reference) | WhatsApp Cloud API | `POST /{Version}/{Phone-Number-ID}/messages` | 2026-10-13 | normative |
| S8 | `https://developers.facebook.com/docs/whatsapp/cloud-api/overview` | Cloud API Overview | WhatsApp Cloud API | none stated for the rate numbers | 2026-10-13 | normative |
| S9 | `https://developers.facebook.com/docs/graph-api/changelog` | Graph API Changelog (index) | Graph API | version availability table, v13.0–v26.0 | 2026-10-13 | normative (index only; per-version pages not fetched) |
| S10 | `https://developers.facebook.com/docs/whatsapp/overview/policy-enforcement` | Policy Enforcement | WhatsApp Business Platform | none stated | 2026-10-13 | normative |
| S11 | `https://developers.facebook.com/community/threads/832353799067029/` | Developer Community thread on 131049 | Meta developer community forum | n/a | 2026-10-13 | **observational, unconfirmed** |

Retrieval failures, recorded so no later agent assumes they were checked:

| Attempted URL | Result |
|---|---|
| `https://developers.facebook.com/docs/whatsapp/cloud-api/guides/health-status` | HTTP 404 |
| `https://developers.facebook.com/documentation/business-messaging/whatsapp/cloud-api/health-status` | returned a JavaScript shell with no body content |
| `https://developers.facebook.com/documentation/business-messaging/whatsapp/cloud-api/reference/messages` | returned a JavaScript shell with no body content (the `/docs/` path, S7, worked) |

The Health Status API is therefore **not checked**. It is the one place a pre-send eligibility check could expose the same codes before a send, and it should be assigned to a later agent.

---

## 2. The rules

**Meta does not publish a request-time error table.** S1/S2 is a single flat reference that mixes send failures, template authoring failures, phone-migration failures, registration failures, analytics-toggle failures and synchronisation failures. It never partitions codes into "returned on the API response" versus "arrives on the `messages` webhook". S2 states the opposite of a partition: it recommends monitoring *both* the synchronous Graph API response and the `messages` webhook, because some errors arrive through either or both. Every statement below about which channel a code arrives on is therefore "not stated" unless a source says otherwise, and the boundary with agent 006 is a documentation boundary Lynomia has to invent, not one Meta provides.

**The error object.** S1/S2 documents these fields, and only these: `message` (the code combined with its title, e.g. the page's own example `(#130429) Rate limit hit`), `type`, `code` (integer), `error_data` containing `messaging_product` (always `whatsapp` for Cloud API) and `details` (a free-text description of the error and its most likely cause, sometimes with the fix), `error_subcode` (marked deprecated), and `fbtrace_id` (to quote to Direct Support). There is **no `title` field**; titles exist only inside `message`. S3 documents two additional fields on the Graph API side that S1/S2 does not mention for Cloud API: `error_user_title` and `error_user_msg`, both localised to the request locale, and `error_user_msg` is described as the message to show the user.

**Meta's own handling instruction.** S1/S2 says to build error handling around `code` and `error_data.details`, explicitly *instead of* subcodes or HTTP response status codes, and says not to rely on titles because titles will eventually be deprecated. This is the single most consequential rule in this report: Meta is telling integrators that neither the HTTP status nor the human-readable title is a stable contract.

**Validation order is not stable.** S5 states that the order in which checks are performed may change, so the same API request can return a different error code depending on which validation fails first. Any Lynomia article of the form "this request returns code X" is therefore unsafe; articles must be written from the code the user actually received, not from the request shape.

**The messages endpoint reference documents no errors at all.** S7 lists a single response, `200`, with the success payload (`messaging_product`, `contacts[].input`, `contacts[].wa_id`, `messages[].id`, `messages[].message_status`). `message_status` is one of `accepted` ("The message has been accepted by WhatsApp and is being processed"), `held_for_quality_assessment`, or `paused`. There is no error-response section and no statement about error HTTP statuses. So a 200 with `message_status` of `held_for_quality_assessment` or `paused` is a *non-failure that is also not a delivery* — a third outcome Lynomia's inbox has to represent and which neither this agent's scope nor agent 006's webhook scope obviously owns.

**HTTP status.** Meta publishes an HTTP status column for exactly one of the ten sections of S1/S2: the Marketing Messages API section (values `400` and `500`). For the other nine sections — including every send failure — **the HTTP status is not stated**. Do not populate an HTTP-status column in any Lynomia article or data model from memory or from community sources.

---

## 3. Error codes and failures

Tables below reproduce S1/S2 section by section, using Meta's own section headings, so every published code is traceable. Columns:

- **Title** — only where Meta publishes one. `not stated` means the section has no title column and the title exists only in the runtime `message` string.
- **HTTP** — `not stated` unless Meta gives it.
- **Retry per Meta** — what Meta actually says. `not stated` where Meta gives no retry guidance; do not infer.
- **Inbox** — relevance to a messaging inbox product: **Y** = outbound send path, **T** = template authoring, **A** = admin / onboarding / number setup, **O** = other (analytics, sync, migration, marketing-ads API).

### 3.1 Authorization errors (S1, S2)

| Code | Subcode | Title | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|---|
| 0 | not stated | not stated | The app user could not be authenticated: token expired or invalidated, or the user blocked app access | not stated | Get a new access token | not stated | Y |
| 3 | not stated | not stated | Capability or permissions problem | not stated | Check app permissions with the access token debugger | not stated | Y |
| 10 | not stated | not stated | Permission not granted or has been removed. Also covers Flows eligibility and phone-number allowlisting for the business public key | not stated | Check permissions; for Flows confirm the number is allowlisted; check API eligibility | not stated | Y |
| 190 | not stated | not stated | Access token expired | not stated | Get a new access token | not stated | Y |
| 200 | not stated | not stated | No access token sent. Observed on some GET endpoints such as `whatsapp_business_profile`; other endpoints may return 190 or 104 instead | not stated | Include a valid access token | not stated | Y |
| 200–299 | not stated | not stated | A **range**, not a code: permission not granted or removed; which permission varies | not stated | Check permissions with the access token debugger | not stated | Y |

Note: **104 has no row of its own.** It is named only inside the 200 row as an alternative code some endpoints return. Lynomia must not create a 104 article claiming a definition Meta has not given.

### 3.2 Integrity errors (S1, S2)

| Code | Subcode | Title | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|---|
| 368 | not stated | not stated | The WABA is restricted or disabled for a platform policy violation | not stated | Review Policy Enforcement and resolve the violation | not stated on S1/S2. **S3 (Graph API) says "wait and retry" for 368, describing it as a temporary block for policy violations** — see §6 | Y |
| 130497 | not stated | not stated | The WABA is restricted from messaging users in certain countries | not stated | Review the WhatsApp Business Messaging Policy for the countries allowed for your business category | not stated | Y |
| 131031 | not stated | not stated | The WABA is restricted or disabled for a policy violation, **or** request data did not match the WABA's data (the page's example: a wrong two-step PIN) | not stated | Review Policy Enforcement; use the Health Status API for detail | not stated | Y |

131031 is the clearest case in the whole corpus of one code carrying two unrelated causes with opposite remedies (policy enforcement vs. a mistyped PIN). Any Lynomia article for 131031 must present both branches.

### 3.3 Template creation errors (S1, S2) — Meta publishes titles here

| Code | Subcode | Title (Meta's words) | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|---|
| 2388039 | not stated | Message template status can't be changed | The template's status cannot be changed, for example while it is in review | not stated | Wait for approval or rejection before editing; daily edit limits apply | not stated | T |
| 2388040 | not stated | Character limit exceeded | A field exceeds its character limit | not stated | Read the error message for the field's limit | not stated | T |
| 2388047 | not stated | Message header format is incorrect | Header formatting is invalid | not stated | Read the error message for valid formatting | not stated | T |
| 2388072 | not stated | Message body format is incorrect | Body formatting is invalid | not stated | Read the error message for valid formatting | not stated | T |
| 2388073 | not stated | Message footer format is incorrect | Footer formatting is invalid | not stated | Read the error message for valid formatting | not stated | T |
| 2388293 | not stated | Parameters words ratio exceeds limit | Too many variables for the template's length | not stated | Reduce variables or lengthen the message | not stated | T |
| 2388299 | not stated | Leading or trailing parameters not allowed | Variables sit at the start or the end of the template | not stated | Move variables away from the start and the end | not stated | T |

### 3.4 Send template errors (S1, S2)

| Code | Subcode | Title (Meta's words) | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|---|
| 2388019 | not stated | Message Template Limit Exceeded | The account reached its template cap | not stated | Stay within the template limit; S1/S2 states 250 templates per WABA | not stated | T |

### 3.5 Phone migration errors (S1, S2) — 2388103 is one code with eleven published variants

| Code | Title / details (Meta's words) | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|
| 2388012 | Phone number already in the WhatsApp account | The number is already present in the account | not stated | Use a number not already in the account | not stated | A |
| 2388091, 2388093 | Not eligible to receive / verify a registration code since the number is not being migrated | The verification APIs do not apply to this case | not stated | Register and verify the number instead | not stated | A |
| 2388103 | Cannot migrate: webhooks not set up on the destination WABA | Destination WABA has no webhook subscription | not stated | Subscribe the app to webhooks on the destination WABA | not stated | A |
| 2388103 | Add this number directly in your WhatsApp account | The number can be added directly rather than migrated | not stated | Register and verify instead of migrating | not stated | A |
| 2388103 | Registered name should be present and approved | Display name missing, unapproved, or a name change is pending | not stated | Get the display name approved | not stated | A |
| 2388103 | Source WhatsApp account not set up correctly | Source WABA not approved, or "messaging on behalf of" not approved; may be using the deprecated On-Behalf-Of model | not stated | Contact support | not stated | A |
| 2388103 | No payment account | No active credit line for sending after migration | not stated | Set up a credit line and share it with the customer | not stated | A |
| 2388103 | Error migrating this phone number | Generic, unspecified migration failure | not stated | Retry later; contact support if it persists | **retry later** | A |
| 2388103 | Belongs to a different Business Manager account | Source and destination WABAs represent different businesses | not stated | Migrate into a WABA for the same business | not stated | A |
| 2388103 | Your WhatsApp account must be approved | Destination WABA not approved | not stated | Complete business verification and get the WABA approved | not stated | A |
| 2388103 | "Messaging For" request must be approved | The client has not accepted the request | not stated | The client accepts it in Meta Business Suite | not stated | A |
| 2494100 | Account is in maintenance mode | The phone number is in maintenance | not stated | Retry in a few minutes | **retry in a few minutes** | A |

**Consequence for Lynomia's error model:** code alone does not identify the failure for 2388103. The discriminator is the `title`/`details` string — the very field Meta says will eventually be deprecated and tells you not to depend on. Agent 000 must decide whether the Meta error taxonomy keys on `code` alone or on `code` plus a details pattern, and 2388103 is the test case that forces the decision.

### 3.6 Template insights errors (S1, S2)

| Code | Title (Meta's words) | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|
| 200005 | Template insights unavailable | Insights are not available for this WABA at the moment | not stated | Cannot be enabled at this time | not stated | O |
| 200006 | Cannot disable template insights | Once enabled, insights cannot be turned off | not stated | None — Meta states this is permanent | **permanent** | O |
| 200007 | Template Insights not enabled | Insights are not enabled for this WABA | not stated | Enable them via the template-analytics confirmation steps | not stated | O |

Note the collision hazard: 200005/200006/200007 sit numerically inside the 200–299 *permission* range of §3.1. Any Lynomia classifier that treats 200–299 as "permission" will misclassify all three.

### 3.7 Synchronization errors (S1, S2)

| Code | Title | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|
| 2593107 | not stated | Sync API call limit exceeded; S1/S2 states one contacts sync and one history sync are allowed | not stated | Offboard the customer and re-onboard | not stated | O |
| 2593108 | not stated | Sync requested more than 24 hours after onboarding | not stated | Offboard and re-onboard | not stated | O |
| 2593109 | History sync is turned off by the business from the WhatsApp Business App (S6) | Returned in a `history` webhook when the business declined to share chat history. S6 notes a successful history-sync API request confirms only acceptance, not sharing | not stated | not stated | not stated | O |

2593109 is documented on S6, not on S1/S2. It is a **webhook** error.

### 3.8 Throttling errors (S1, S2)

| Code | Subcode | Title | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|---|
| 4 | not stated | not stated | The app reached its API call rate limit | not stated | Check the rate limit in the App Dashboard; retry later or reduce calls | **retry later / reduce calls**; S3 also says wait and retry | Y |
| 80007 | not stated | not stated | The WABA reached its rate limit | not stated | Retry later or reduce calls | **retry later / reduce calls** | Y |
| 130429 | not stated | `Rate limit hit` (from the example `message` string on S1, not from a title column) | Cloud API message throughput reached | not stated | Retry later or slow the send rate | **retry later** | Y |
| 131048 | not stated | not stated | Sending is restricted for this number, likely because too many messages were blocked or flagged as spam | not stated | Check quality status in WhatsApp Manager; review template limits and quality | not stated | Y |
| 131056 | not stated | not stated | Too many messages between this sender and this recipient in a short period | not stated | Wait before messaging that recipient; other recipients are unaffected | **wait, then retry** | Y |
| 133016 | not stated | not stated | Too many registration or deregistration attempts | not stated | Wait until the number is unblocked; see Registration limitations | **wait until unblocked** | A |
| 131064 | not stated | not stated | Messaging limit arising from template classification violations | not stated | Review template classifications; the restriction lifts after the enforcement period | **lifts after the enforcement period** (duration not stated) | Y |

S4 (Graph API Rate Limiting) **does not document 80007, 130429, 131048 or 368**. Its Business-Use-Case table assigns `80008` to the WhatsApp Business Management API; it does not list 80007 at all. Code 4 appears there only in the platform-throttle table with no subcode. So the WhatsApp throttling codes and the Graph API rate-limit codes are two disjoint published sets, and a Lynomia article cannot cite S4 as the definition of 80007.

### 3.9 Other errors (S1, S2) — the full 43-code list, in Meta's order of appearance

| Code | Subcode | Title | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|---|
| 1 | not stated | not stated | Invalid request, or a possible server error | not stated | Check platform status; verify request format and the endpoint's requirements | not stated on S1/S2; **S3 says wait and retry, "possibly temporary"** | Y |
| 2 | not stated | not stated | Temporary downtime or overload | not stated | Check platform status, then retry | **retry** | Y |
| 33 | not stated | not stated | The business phone number has been deleted | not stated | Verify the phone number | not stated | A |
| 100 | not stated | `Invalid parameter` (title published only in the MM API table) | Unsupported or misspelled parameters. Also covers Flows public-key format, a phone-number-ID mismatch, and length limits | not stated for Cloud API (**400** in the MM API table) | Check the endpoint's parameters and length limits; verify key format and phone number ID | not stated | Y |
| 130403 | not stated | not stated | The business is blocked by the end user | not stated | **Do not retry**; the user must unblock the business | **do not retry** | Y |
| 130472 | not stated | not stated | The message was not sent as part of an experiment | not stated | See Marketing Message Experiment | not stated | O |
| 131000 | not stated | not stated | Unknown error. Also covers Flows signature and GraphQL failures | not stated | Retry; open a Direct Support ticket if it persists | **retry** | Y |
| 131005 | not stated | not stated | Permission not granted or has been removed | not stated | Check permissions with the access token debugger | not stated | Y |
| 131008 | not stated | not stated | A required parameter is missing | not stated | Check the endpoint's required parameters | not stated | Y |
| 131009 | not stated | `Parameter value is not valid` (MM API table) | One or more parameter values are invalid | not stated for Cloud API (**400** in the MM API table) | Check supported values; see the Phone Numbers guidance | not stated for Cloud API; the MM API variant says wait 10 minutes for ad syncing | Y |
| 131016 | not stated | not stated | Service temporarily unavailable | not stated | Check platform status, then retry | **retry** | Y |
| 131021 | not stated | not stated | Sender and recipient are the same phone number | not stated | Send to a different number | not stated | Y |
| 131026 | not stated | not stated | Message undeliverable: the recipient is not a WhatsApp user, has not accepted the terms, or runs an outdated client | not stated | Have the user confirm they can be messaged, accept the terms, and update WhatsApp (minimum versions in §4) | not stated | Y |
| 131037 | not stated | not stated | A `555` test number has no approved display name | not stated | Get the display name approved | not stated | A |
| 131042 | not stated | not stated | Payment method / billing error: billing setup, credit limit, account status, or MessagingFor problems | not stated | Review billing setup against the page's list of common causes | not stated | Y |
| 131045 | not stated | not stated | Phone number registration error | not stated | Register the number, then retry | **retry after registering** | Y |
| 131047 | not stated | not stated | More than 24 hours have passed since the recipient last replied | not stated | Send a template message instead | not stated (remedy is a different message, not a retry) | Y |
| 131049 | not stated | not stated | The message was not delivered in order to maintain healthy ecosystem engagement — the per-user marketing limit | not stated | **Wait at least 24 hours before resending**; see per-user limits | **wait ≥24 hours** | Y |
| 131050 | not stated | not stated | The recipient has opted out of marketing messages | not stated | **Do not retry**; subscribe to the `user_preferences` webhook | **do not retry** | Y |
| 131051 | not stated | not stated | Unsupported message type | not stated | Use a supported type | not stated | Y |
| 131052 | not stated | not stated | Could not download the media the user sent | not stated | Check the error details on the `messages` webhook; ask the user to resend the media another way | not stated | Y (inbound; **webhook-side**) |
| 131053 | not stated | not stated | Could not upload the media, for example an unsupported type | not stated | Check the file's MIME type against the supported media types | not stated | Y |
| 131055 | not stated | `Method not allowed` (MM API table) | A non-marketing template (utility, authentication, or a non-template message) was sent to the Marketing Messages API | **400** | Send a marketing template | not stated | O |
| 131057 | not stated | not stated | The business account is in maintenance mode; may be due to a throughput upgrade | not stated | Wait for maintenance to end | **wait** | Y |
| 131063 | not stated | not stated | Marketing templates are disabled on Cloud API for this business | not stated | Use the Marketing Messages API, or re-enable marketing messages on Cloud API (S1 names the setting `disable_marketing_messages_on_cloud_api` set to `false`) | not stated | Y |
| 132000 | not stated | not stated | The number of parameters supplied does not match the template | not stated | Send values for all of the template's parameters | not stated | Y |
| 132001 | not stated | not stated | The template does not exist in that language, or is not approved | not stated | Confirm approval, name and locale | not stated | Y |
| 132005 | not stated | not stated | The translated text is too long | not stated | Check the translation in WhatsApp Manager | not stated | Y |
| 132007 | not stated | not stated | The template content violates a WhatsApp policy | not stated | Review the template review guidance | not stated | Y |
| 132012 | not stated | not stated | Parameter values are formatted incorrectly | not stated | Match the template's parameter format | not stated | Y |
| 132015 | not stated | not stated | The template is paused for low quality | not stated | Edit the template to improve quality; resend after approval | not stated | Y |
| 132016 | not stated | not stated | The template was paused too many times and is permanently disabled | not stated | Create a new template | **permanent for that template** | Y |
| 132018 | not stated | `Template validation error` (MM API table) | Parameter problems in the template | **400** | Fix the parameters and resend | retry after fixing | O |
| 132068 | not stated | not stated | The Flow is blocked | not stated | Correct the Flow | not stated | Y |
| 132069 | not stated | not stated | The Flow is throttled — 10 messages already sent in the last hour | not stated | Correct the Flow | not stated | Y |
| 133000 | not stated | not stated | A previous deregistration failed | not stated | Deregister again before registering | not stated | A |
| 133004 | not stated | not stated | Server temporarily unavailable | not stated | Check platform status and `details`, then retry | **retry** | Y |
| 133005 | not stated | not stated | The two-step verification PIN is incorrect | not stated | Verify the PIN; to reset it, disable it and set a new one | not stated | A |
| 133006 | not stated | not stated | The phone number must be verified before registering | not stated | Verify the number, then register it | not stated | A |
| 133008 | not stated | not stated | Too many PIN guesses | not stated | Wait the time given in `details` | **wait the time in `details`** | A |
| 133009 | not stated | not stated | The PIN was entered too quickly | not stated | Check `details` and wait before retrying | **wait** | A |
| 133010 | not stated | not stated | The phone number is not registered | not stated | Register the number | not stated | A |
| 133015 | not stated | not stated | The number was recently deleted and the deletion is not complete | not stated | **Wait 5 minutes** and retry | **wait 5 minutes** | A |
| 134011 | not stated | not stated | WhatsApp Payments terms are pending acceptance | not stated | Accept the terms using the link in the error message | not stated | O |
| 135000 | not stated | not stated | Unknown error with the request parameters | not stated | Check the endpoint's syntax; contact customer support if it continues | not stated | Y |

### 3.10 Marketing Messages API for WhatsApp (S1, S2) — the only section with HTTP statuses

| Code | Title (Meta's `message` value) | What it means | HTTP | Business action | Retry per Meta | Inbox |
|---|---|---|---|---|---|---|
| 100 | `(#100) Invalid parameter` | A non-template message was sent | 400 Bad Request | Send a marketing template with `type` `template` | not stated | O |
| 131009 | `(#131009) Parameter value is not valid` | Invalid parameter, possibly because ad syncing is incomplete | 400 Bad Request | Check valid parameters; wait 10 minutes; contact support if it persists | **wait 10 minutes** | O |
| 131055 | `(#131055) Method not allowed` | A utility, authentication or non-template message was sent | 400 Bad Request | Send a marketing template | not stated | O |
| 134100 | `(#134100) Only marketing messages supported` | A utility or authentication template was sent. Available from Graph API v23.0 | 400 Bad Request | Use only `MARKETING` templates | not stated | O |
| 134101 | `(#134101) Your template is still syncing` | A newly created template has not finished ad syncing. Available from Graph API v23.0 | 400 Bad Request | Wait up to about 10 minutes, then retry | **wait ~10 minutes** | O |
| 134102 | `(#134102) Template unavailable for use` | Ad sync failed, or the account is not eligible. Available from Graph API v23.0 | 500 Internal Server Error | Check eligibility; contact support if the status is `ONBOARDED` and it persists | not stated | O |
| 132018 | `(#132018) Template validation error` | Parameter problems in the template | 400 Bad Request | Fix the parameters and resend | retry after fixing | O |
| 1752041 | `(#1752041) Duplicate Request` | The client was already invited to onboard by a partner | 400 Bad Request | No action needed; the existing onboarding covers all eligible WABAs | not applicable | O |

### 3.11 Graph API generic codes and authentication subcodes (S3)

These are the Graph-API-level definitions. They overlap S1/S2 for codes 1, 2, 3, 4, 10, 190, 200–299 and 368, and they are the **only** published source of retryability for several of them.

| Code / subcode | Name (Meta's words) | Meta's recommended handling | Retryable per S3 |
|---|---|---|---|
| 1 | API Unknown | Wait and retry; if it recurs, confirm the API exists | yes, "possibly temporary" |
| 2 | API Service | Wait and retry | yes |
| 3 | API Method | Ensure the app has the required capability or permission | no |
| 4 | API Too Many Calls | Wait and retry, or reduce request volume | yes (throttling) |
| 10 | API Permission Denied | Handle the missing permission | no |
| 17 | API User Too Many Calls | Wait and retry, or reduce request volume | yes (throttling) |
| 102 | API Session | Get a new access token | no — fix the token |
| 190 | Access token expired | Get a new access token | no — fix the token |
| 200–299 | API Permission | Handle the missing permission; varies by permission | no |
| 341 | Application limit reached | Wait and retry, or reduce request volume | yes |
| 368 | Temporarily blocked for policy violations | Wait and retry | yes, temporary — **conflicts with S1/S2, see §6** |
| 506 | Duplicate Post | Change the content, then retry | only after changing content |
| 1609005 | Error Posting Link | Check the URL, then retry | only after checking the URL |
| subcode 458 | App Not Installed | The user has not logged into the app; reauthenticate | n/a |
| subcode 459 | User Checkpointed | The user must log in on facebook.com or m.facebook.com to resolve an issue | n/a |
| subcode 460 | Password Changed | On iOS 6+ with OS-integrated login, send the user to device Facebook settings; otherwise they must log into the app again | n/a |
| subcode 463 | Expired | Token or login status expired, revoked or invalid | n/a |
| subcode 464 | Unconfirmed User | The user must log in on facebook.com or m.facebook.com | n/a |
| subcode 467 | Invalid Access Token | Token expired, revoked or invalid | n/a |
| subcode 492 | Invalid Session | The user behind the Page access token lacks an appropriate Page role | n/a |

S3 documents no subcode 490, no HTTP statuses, and no rate-limit headers.

### 3.12 Subcodes

The only `error_subcode` value that appears anywhere in this scope is **2494055**, in the example error response on S1. **Its meaning is not stated.** Everything else in this scope has no published subcode: S1/S2 marks `error_subcode` deprecated and says it is not returned in v16.0+, and none of its nine Cloud API tables has a subcode column. The subcodes in §3.11 are Graph API *authentication* subcodes under code 190/102, not WhatsApp send subcodes. **No WhatsApp send failure in this report has a documented subcode.**

### 3.13 Codes Lynomia or the wider internet may expect that Meta does **not** document here

Checked against S1/S2 on 2026-10-13 and **absent**: 131058, 131060, 131062, 130495.

- **131060** is real but out of this agent's scope. S6 documents it as an **unsupported `messages` webhook** error that may follow onboarding of a WhatsApp Business app number, and says it is expected in two scenarios: a WhatsApp user messaging the business for the first time, often after tapping a click-to-WhatsApp ad, which S6 says typically resolves within a few seconds after which messages deliver normally; and a user with an unsupported companion device sending or receiving a message. S6's remedy is to tell the business to check the WhatsApp Business app for the message. **It is not a request-time send failure and it is not a failure of the integration.** The Lynomia corpus already carries `custom/db/documentation/en/whatsapp-errors/whatsapp-error-131060.md`, so that article is scoped against the wrong channel and against a code the main error reference does not list. Route to agents 006 and 054.
- **131058, 131062, 130495** are not on any page fetched for this report. Do not create articles for them from this agent's evidence.

### 3.14 What the end user sees

Meta states almost nothing about the end-user-visible effect, and §3's tables omit a column that would be `not stated` in nearly every row. What is stated:

| Code | What Meta says the end user experiences | Source |
|---|---|---|
| 130403 | The user has blocked the business; the message does not reach them and the user must unblock the business | S1, S2 |
| 131050 | The user opted out of marketing messages; delivery is suppressed, and the `user_preferences` webhook is the signal | S1, S2 |
| 131049 | The message was withheld to maintain healthy ecosystem engagement; the user receives nothing | S1, S2 |
| 131026 | The recipient is not a WhatsApp user, has not accepted the terms, or runs a client older than the minimum versions in §4 | S1 |
| 131060 | Per S6 the message may still be visible in the business's WhatsApp Business app; the user side is not described | S6 |

For every other code in §3, **what the end user sees is not stated**. Lynomia articles must not assert it.

---

## 4. Limits and numbers

Only numbers a source literally states.

| Number | Statement | Source |
|---|---|---|
| 80 messages / second | "Business phone numbers can send up to 80 messages per second by default", with capacity upgrades available | S8 |
| 1 message / 6 seconds to the same user | "Business phone numbers can send 1 message every 6 seconds to the same WhatsApp user." The page also gives 0.17 messages/second, about 10 per minute, and 600 per hour | S8 |
| 45 messages in a 6-second burst | "You may send up to 45 messages in a 6-second burst"; burst use is borrowed from future quota | S8 |
| `4^X` seconds | Retry backoff after a failed send: "retry after 4^X seconds (starting with X=0 and increasing X by 1 after each failure) until successful" | S8 |
| Capacity rate limit | Listed as a limit type for all accounts; **no number stated** | S8 |
| Higher throughput for verified business portfolios | Stated; **no number** | S8 |
| 250 templates per WABA | The template limit behind 2388019 | S1, S2 |
| 200 requests / hour / app / WABA | Default Business Management API limit | S4, S8 |
| 5,000 requests / hour / app / active WABA | For WABAs with at least one registered phone number | S4, S8 |
| 5,000 requests / hour | Credit Line API | S4, S8 |
| up to 32 objects | `X-Business-Use-Case-Usage` can return up to 32 objects in one call | S4 |
| 10 messages in the last hour | The Flow throttle behind 132069 | S1, S2 |
| 1 contacts sync + 1 history sync | The limit behind 2593107 | S1, S2 |
| 24 hours | 2593108: a sync requested more than 24 hours after onboarding fails | S1, S2 |
| 24 hours | 131047: more than 24 hours since the recipient last replied | S1, S2 |
| at least 24 hours | 131049: wait before resending | S1, S2 |
| 5 minutes | 133015: wait after a recent number deletion | S1, S2 |
| ~10 minutes | 134101 / MM API 131009: ad syncing | S1, S2 |
| a few minutes | 2494100: maintenance mode | S1, S2 |
| 1 or 3 days | Policy enforcement: block on sending marketing, utility and authentication templates, and on adding phone numbers | S10 |
| 5, 7 or 30 days | Policy enforcement: block on sending any messages, and on adding phone numbers | S10 |
| indefinite | Policy enforcement: account lock, liftable only by appeal | S10 |
| permanent | Policy enforcement: permanent disablement from the WhatsApp Business Platform after repeated warnings and restrictions with no change | S10 |
| Android 2.21.15.15 / SMBA 2.21.15.15 / iOS 2.21.170.4 / SMBI 2.21.170.4 / KaiOS 2.2130.10 / Web 2.2132.6 | Minimum WhatsApp client versions cited under 131026 | S1 |

Rate-limit headers (S4): `X-App-Usage` with `call_count`, `total_time`, `total_cputime`; `X-Business-Use-Case-Usage` with `business-id`, `call_count`, `total_cputime`, `total_time`, `estimated_time_to_regain_access`, `type`, `ads_api_access_tier`; `X-Ad-Account-Usage` (Ads API v3.3 and older) with `acc_id_util_pct`, `reset_time_duration`, `ads_api_access_tier`. S4 states `estimated_time_to_regain_access` is the time in minutes until calls will no longer be throttled, says to stop making API calls when the limit is reached because continued calls increase the count and delay recovery, and gives **no backoff algorithm** of its own — the only published backoff is S8's `4^X`.

---

## 5. Version and deprecation notes

| Item | Statement | Version | Source |
|---|---|---|---|
| `error_subcode` | Deprecated; "Will not be returned in v16.0+ responses" | v16.0 | S1, S2 |
| Error titles | Meta recommends not relying on titles for error handling because titles will eventually be deprecated | not stated | S1, S2 |
| HTTP status as a handling key | Meta says to build handling around error codes "instead of subcodes or HTTP response status codes" | not stated | S1, S2 |
| 134100, 134101, 134102 | Available from Graph API v23.0 | v23.0 | S1, S2 |
| On-Behalf-Of (OBO) model | Described as deprecated, inside the 2388103 "source WhatsApp account not set up correctly" row | not stated | S2 |
| Latest Graph API version | v26.0, introduced 2026-07-29, "Available Until" TBD | v26.0 | S9 |
| Version availability | S9's table gives: v25.0 (2026-02-18 → 2028-07-29), v24.0 (2025-10-08 → 2028-02-18), v23.0 (2025-05-29 → 2027-10-08), v22.0 (2025-01-21 → 2027-05-20), v21.0 (2024-10-02 → 2027-01-21), v20.0 (2024-05-21 → 2026-09-24), v19.0 (2024-01-23 → 2026-05-21), v18.0 (2023-09-12 → 2026-01-26), v17.0, v16.0, v15.0, v14.0, v13.0 all with earlier end dates | — | S9 |
| Derived from S9, not stated by Meta | Comparing S9's stated "Available Until" dates against today, 2026-10-13: **v20.0 and every earlier version are past their stated availability date.** The earliest version whose stated end date is still in the future is v21.0 (2027-01-21) | — | arithmetic on S9 |
| Documentation path migration | The canonical path has moved from `developers.facebook.com/docs/whatsapp/...` to `developers.facebook.com/documentation/business-messaging/whatsapp/...`. Both served equivalent content for the error reference on 2026-10-13. Some pages render **only** on the old `/docs/` path (S7) and some only on the new path (S6) | — | S1, S2, S6, S7 |

Per-version changelog pages were **not fetched** — S9 is the index only. Whether any specific WhatsApp error code was added, renamed or removed in a given version is therefore **not checked**, and should be assigned to agent 025 or 091.

---

## 6. Ambiguities and gaps

1. **Meta publishes no HTTP status for message-send failures.** Nine of the ten sections of S1/S2 have no HTTP status column; only the Marketing Messages API section does. The brief asks for "the HTTP status" per code and the honest answer is that it is not stated, and Meta actively discourages keying on it. If the Lynomia error model has an `http_status` column, it will be empty for every send failure, or populated from a non-normative source. **Agent 000 decision: drop the column, or mark it explicitly non-normative.**
2. **Request-time versus webhook is not partitioned anywhere.** S2 says to watch both the synchronous response and the `messages` webhook because some errors arrive through either or both. The split between this agent's scope and agent 006's is a Lynomia invention. The only codes with a stated channel are 131060 and 2593109 (webhook, S6) and 131052 (the details live on the `messages` webhook, S1/S2). **This must be arbitrated with agent 006 before any article is written that says "at send time you get X".**
3. **Validation order is explicitly unstable (S5).** Documentation cannot promise that a given malformed request yields a given code. Articles must be organised by received code, not by request defect.
4. **Retryability is published for a minority of codes.** Meta states retry guidance for roughly 20 of the ~100 rows in §3. For the rest it is `not stated`, and §3's tables say so rather than guessing. A "retryable" flag in the Lynomia model will be unknown for most codes.
5. **368 conflicts across Meta's own sources.** S3 (Graph API) calls 368 a *temporary* block for policy violations and says to wait and retry. S1/S2 (WhatsApp) calls it a WABA restricted or disabled for a platform policy violation and says to resolve the violation. S10 shows enforcement durations ranging from 1 day to permanent disablement. These are not reconcilable from the published text. **Route to agent 028 / 088.**
6. **2388103 carries eleven distinct failures under one code**, discriminated only by the title/details string that Meta says not to depend on. See §3.5.
7. **200–299 is a range and 200005/200006/200007 fall inside it numerically** while meaning something unrelated. A naive numeric classifier breaks. See §3.6.
8. **104 is named but never defined** (inside the 200 row). No definition exists to document.
9. **`error_data.details` is the field Meta tells you to build on, and Meta publishes no catalogue of its values.** The strings are the real discriminator for 2388103, 131042, 131026, 133008, 133009, 131052 and 133004, and none of them is enumerated. This is the single largest gap in Meta's published error surface.
10. **`error_subcode` 2494055 appears in Meta's own example response with no stated meaning**, on a page that simultaneously marks subcodes deprecated.
11. **131048 versus 131049.** Both are currently documented, in different sections, with different meanings. A developer community thread (S11) claims 131048 "has been replaced with" 131049. That is **observational, unconfirmed**, it comes from a forum and not from documentation, and it is contradicted by the current page listing both codes. Do not repeat it.
12. **131031's two causes have opposite remedies** (policy enforcement vs. a wrong two-step PIN). See §3.2.
13. **A 200 response is not necessarily a send.** S7's `message_status` can be `held_for_quality_assessment` or `paused`, and neither is defined on that page. Neither this agent's scope nor agent 006's clearly owns them. **Route to agent 000.**
14. **The capacity rate limit has no published number** (S8), yet it is one of the four named message rate limits and is the most likely cause of 130429 at scale.
15. **The Health Status API was not checked** — 404 on the `/docs/` path, JS shell on the new path. It is the only candidate for a pre-send eligibility check and it is referenced by the 131031 row as the place to get detail. **Needs a re-attempt by a later agent.**
16. **No page states which codes can appear for a template send versus a free-form send**, even though 132000/132001/132005/132012/132015/132016 are obviously template-only. The grouping in §3.9 is Meta's ("Other errors"), not functional.

---

## 7. What Lynomia users would ask

A support desk receiving these failures will be asked, in roughly this order of volume:

1. "My message says failed but I do not know why" — the inbox shows a code with no explanation. The need is a code lookup reachable from the failed message itself, keyed on the code the API returned, since §6.3 rules out inferring the code from the request.
2. "Can I just send it again?" — answerable for about twenty codes and **not** answerable for the rest. The article pattern must distinguish "Meta says do not retry" (130403, 131050), "Meta says wait a stated time" (131049 ≥24h, 133015 5 min, 134101 ~10 min, 2494100 a few minutes, 133008 the time in `details`), "Meta says retry" (1, 2, 4, 80007, 130429, 131000, 131016, 133004) and "Meta does not say".
3. "Why can I reply to some customers and not others?" — 131047 (the 24-hour window) versus 131026 (the recipient cannot receive) versus 130403 (blocked) versus 131050 (opted out) versus 131049 (withheld). Five codes, five different user explanations, and today's corpus covers one of them.
4. "The template exists and is approved, so why was it rejected on send?" — 132001 versus 132000 versus 132012 versus 132005 versus 132015 versus 132016. The distinction between a language/name resolution failure and a parameter failure is the most common template support question and it is entirely a code-level distinction.
5. "We are suddenly rate limited" — 130429 versus 80007 versus 4 versus 131056 versus 131048 versus 131064. The business needs to know which of the six is per-app, per-WABA, per-number, per-recipient-pair, quality-driven or enforcement-driven, because the remedy differs and only `4^X` backoff (S8) is published.
6. "Is our account in trouble?" — 368, 130497, 131031, 131064, 132015, 132016, plus S10's durations. Users want to know how long, and S10 gives 1/3 days, 5/7/30 days, indefinite, permanent — but **associates no error code with any duration**.
7. "Billing is set up but sends fail" — 131042's several causes, and the 2388103 "no payment account" variant.
8. "Why did media fail?" — 131053 on the outbound side (MIME type), 131052 on the inbound side (webhook). Two codes that look like one problem to a user and live on opposite sides of the request/webhook boundary.
9. "What happened to error 131060?" — the corpus has an article for a code that is not in the error reference and is not a send failure (§3.13).

The highest-value documentation asset this scope produces is not prose. It is a **complete, code-keyed, provenance-carrying error table** of the ~100 rows in §3, with the honest `not stated` cells preserved, reachable from a failed message in the inbox. Every cell that says `not stated` in this report must stay `not stated` in the product; the existing corpus has a per-code article for four codes in this scope (190, 131042, 131049, 131053 — `custom/db/documentation/en/whatsapp-errors/whatsapp-error-{190,131042,131049,131053}.md`) plus one out-of-scope code (131060), against roughly 100 that Meta publishes.
