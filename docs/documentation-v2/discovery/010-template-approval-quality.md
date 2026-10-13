---
agent: 010
scope: WhatsApp template approval — statuses, rejection reasons, review and appeals, quality rating, pausing/disabling, status and quality webhooks, post-approval category re-classification
confidence: high
sources_normative: 10
sources_observational: 1
---

## 1. Source register

Every claim below cites a row ID. Date checked for all rows: **2026-10-13**.

| # | Source URL | Page title | Product | API / version context | Normative? |
|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates` | Template fundamentals | WhatsApp Business Platform (Business Management API) | none stated; page is version-independent | normative |
| S2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-review.md` | Template review | WhatsApp Business Platform | none stated | normative |
| S3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-pausing.md` | Template pausing | WhatsApp Business Platform | none stated; rollout dates given | normative |
| S4 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-quality.md` | Template quality rating | WhatsApp Business Platform | examples use Graph API `v25.0` | normative |
| S5 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-categorization.md` | Template categorization | WhatsApp Business Platform | none stated; effective dates given | normative |
| S6 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-management.md` | Template management | WhatsApp Business Platform (Business Management API) | none stated | normative |
| S7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-pacing.md` | Template pacing | WhatsApp Business Platform | `message_status` stated to appear on all API versions | normative |
| S8 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/message_template_status_update.md` | Webhook reference: `message_template_status_update` | WhatsApp Business Platform webhooks | object `whatsapp_business_account` | normative |
| S9 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/message_template_quality_update.md` | Webhook reference: `message_template_quality_update` | WhatsApp Business Platform webhooks | object `whatsapp_business_account` | normative |
| S10 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog.md` | WhatsApp changelog | WhatsApp Business Platform | per-entry, see §5 | **observational** (a changelog, per program §6.2, even though Meta-authored) |
| S11 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/llms.txt` | Full documentation index | WhatsApp Business Platform | n/a | normative (index of canonical page URLs) |

**URLs that could not be read** (recorded so no later agent repeats the attempt): `/docs/whatsapp/business-management-api/message-templates/guidelines` → HTTP 404; `/docs/whatsapp/message-templates/review` → HTTP 404; `/documentation/business-messaging/whatsapp/templates/review` (no `.md`) and `/docs/graph-api/webhooks/reference/whatsapp-business-account/` → returned navigation chrome only, no article body. **The `.md` suffix on any path listed in S11 returns the full plain-text article and is the reliable way to read these pages.** This is worth recording as a program-wide technique for agents 001–028.

**Boundary.** Creation, components, variables and creation-time limits belong to agent 009. Send-time parameter and language failures belong to agent 011. This report covers only the interval between a successful create and a successful send: review, status, quality, pausing, and re-classification. Where a send-time error code is the *only* documented consequence of a status (132015/132016/2061/2062) it is recorded in §3 because the status is meaningless without it.

---

## 2. The rules

### 2.1 The one rule that governs sending

A template must be in status `APPROVED` to be used in a template message. S1 states it twice: templates must have a status of `APPROVED` before they can be sent, and a template that is rejected or whose status changes to any other value cannot be sent in template messages. S4 repeats it from the quality side: if the status changes to anything other than `APPROVED`, the template cannot be sent until `APPROVED` is restored. Every other rule in this report is a way of leaving or re-entering `APPROVED`.

### 2.2 Status values

Two overlapping vocabularies exist and Meta does not reconcile them on any page read.

**(a) The webhook `event` enum** — the complete documented set, from S8:

`APPROVED`, `ARCHIVED`, `UNARCHIVED`, `DELETED`, `DISABLED`, `FLAGGED`, `IN_APPEAL`, `LIMIT_EXCEEDED`, `LOCKED`, `PAUSED`, `PENDING`, `REINSTATED`, `PENDING_DELETION`, `REJECTED`.

**(b) The API `status` field** — S6 names `APPROVED`, `PENDING`, `REJECTED`, `PAUSED`, `PENDING_DELETION` in its examples and rules, and refers to a "disabled status" in prose without giving its enum spelling. S6 shows `status` being filtered with lowercase values (`status=approved`, `status=rejected`).

| Status | What the sources state it means | Can it be sent? | Source |
|---|---|---|---|
| `PENDING` | Under review. WhatsApp Manager label **In-Review**. Also the state of a template that was edited and resubmitted. | No (not `APPROVED`) | S1, S5, S6, S3 |
| `APPROVED` | Passed review; WhatsApp agreed with the submitted category. WhatsApp Manager splits this into four quality labels (§2.5). | Yes | S1, S5 |
| `REJECTED` | Failed review, or violates one or more policies. Also the terminal state of a template that Meta re-classifies **to** `AUTHENTICATION` (§2.8). May be edited without limit. | No | S1, S5, S6 |
| `PAUSED` | Paused for recurring negative feedback or low read-rates (§2.6), or paused by Template Pacing (§2.7). May be edited. | No | S1, S3, S7 |
| Disabled (`DISABLED` as a webhook event; API enum spelling **not stated**) | Disabled for recurring negative feedback; reached on the third pause instance. Templates in a disabled status cannot be deleted. | No | S1, S3, S6 |
| `IN_APPEAL` | WhatsApp Manager label **Appeal Requested**: "indicates that an appeal has been requested". No further definition given. | not stated | S1, S8 |
| `PENDING_DELETION` | Set when a template that has been sent but not yet delivered is deleted; WhatsApp continues delivery attempts for 30 days. On a `PENDING_DELETION` webhook the `reason` field is `null`. | No | S6, S8 |
| `ARCHIVED` / `UNARCHIVED` | Not defined on the pages read. S1 documents the underlying mechanism: a template inactive for 12 months or more is archived, and is deleted 28 days later unless unarchived. | not stated | S1, S8 |
| `DELETED` | Not defined on the pages read. | n/a | S8 |
| `FLAGGED`, `LOCKED`, `LIMIT_EXCEEDED`, `REINSTATED` | **Not defined on any page read.** `LOCKED` is the only one with an indirect trace: S8 says `other_info` appears "for locked or unlocked templates", yet the documented `other_info.title` values are all pause/unpause values. | not stated | S8 |

That last row is a real documentation hole, not a reading failure: four values a production webhook can deliver have no documented meaning. See §6.

### 2.3 Review: what happens and how long it takes

S2 states that templates go through automated systems **and** manual review against WhatsApp's policies and quality standards, that Cloud API uses machine learning to review templates and their variable parameters, and that no information from that review is shared with WhatsApp. Templates containing spam, scam-like content, or policy violations are rejected during review. Templates with variables must carry sample values — including media and text — so reviewers can see the rendered message.

**An approval decision can take up to 24 hours** (S1 and S2 both state 24 hours). The decision is delivered four ways (S2): a notification in WhatsApp Manager, email to the Meta Business Suite admins, the `message_template_status_update` webhook, and — for rejections — a `Rejected message templates` entry in Business Support Home.

### 2.4 Rejection reasons

The `reason` enum from S8 is the authoritative list:

| `reason` value | What Meta states about it | Source |
|---|---|---|
| `NONE` | Carried on an `APPROVED` event — i.e. "no rejection reason". | S8 |
| `INVALID_FORMAT` | The only reason for which the webhook populates `rejection_info` (`rejection_info.reason` and `rejection_info.recommendation`). The S8 example `REJECTED` payload uses this value. | S8 |
| `ABUSIVE_CONTENT` | Listed in the enum; **no definition or trigger given on any page read**. | S8 |
| `SCAM` | Listed in the enum; **no definition given**. S2 states separately that scam-like content is rejected during review. | S8, S2 |
| `PROMOTIONAL` | Listed in the enum; **no definition given**, and its relationship to `INCORRECT_CATEGORY` is not stated. | S8 |
| `INCORRECT_CATEGORY` | Normative and well documented: WhatsApp disagreed with the submitted category. Remedies: create a new template, edit the category and resubmit, or request a review. | S5, S8 |
| `TAG_CONTENT_MISMATCH` | Listed in the enum; **no definition given on any page read**. | S8 |
| `CATEGORY_NOT_AVAILABLE` | Listed as **deprecated**. | S8 |

**What actually triggers a rejection.** S2 lists the triggers in prose but **does not map any of them to an enum value**. The mapping below is therefore split: the left column is normative prose, the right column is my inference and is labelled as such.

| Trigger stated by Meta (S2) | Probable `reason` (inference, not stated) |
|---|---|
| Parameter formatting: missing or mismatched curly braces; special characters such as `#`, `$` or `%`; non-sequential parameters; too many parameters for the message length; a template that starts or ends with a parameter | `INVALID_FORMAT` — inference |
| Content that breaks the WhatsApp Commerce Policy | not inferable |
| Requesting sensitive identifiers — full card numbers, full financial account numbers, national ID numbers (partial identifiers are allowed) | not inferable |
| Abusive or threatening content, such as threatening legal action or public shaming | `ABUSIVE_CONTENT` — inference |
| Exceeding the body character limit (which S2 says varies by format and tag) or the emoji cap | `INVALID_FORMAT` — inference |
| A template whose **body and footer wording duplicates an existing template**. This check does **not** apply to `AUTHENTICATION` templates. Business Support Home names the duplicate template and its language. | not inferable |

### 2.5 Appeals

**Content appeals** (S2, repeated in S3): a rejected submission may be appealed, and **the appeal must include a sample**. The WhatsApp Manager path is Account tools → Message templates → select the template → edit → **Add Sample** → add sample variable values and images → **Submit**. The appeal is reviewed and decided **within 24 hours**. If an approved template later becomes disabled, S2 says to edit and resubmit it instead of appealing. No API endpoint for lodging a content appeal appears on any page read — the only template-lifecycle `POST` documented outside create/edit is `/{whats_app_message_template_id}/unpause` (S3).

**Category appeals** are a separate mechanism with its own rules (S5): requestable only in WhatsApp Manager, via Business Support → Template Category Updates. Eligible: a `UTILITY` or `MARKETING` template that is `REJECTED`, and a `MARKETING` template that is `APPROVED`. A template merely *heading for* rejection cannot be reviewed. The window is **60 days** to review and appeal changes in Business Support Home, and review requests for approved templates are accepted up to **60 days** from the creation or category-update date. For a pending utility→marketing change, a successful review prevents the change; a failed review lets it proceed. An approved review fires `template_category_update` with `new_category`; a denied review leaves the category unchanged.

### 2.6 Quality rating, pausing and disabling

**The rating.** S4 defines four values of the per-template `quality_score.score`, retrievable as the `quality_score` field on the Template API (the response carries `score` and a `date` of last update):

| Value | WhatsApp Manager label | What Meta states | Sendable? |
|---|---|---|---|
| `UNKNOWN` | Active - Quality pending | Not enough user feedback or read-rate data yet; new templates start here | Yes |
| `GREEN` | Active - High quality | Little to no negative feedback from WhatsApp users | Yes |
| `YELLOW` | Active - Medium quality | Negative feedback from multiple users, or low read-rates; may soon be paused or disabled | Yes |
| `RED` | Active - Low quality | Same causes; at risk of being paused or disabled soon | Yes, but see pausing |

**How it is computed.** S4 and S1 both say only that the rating is based on **usage, customer feedback and engagement**, that WhatsApp updates it automatically as signals accumulate, and that the negative signals are negative feedback from multiple users and low read-rates. **No formula, no weighting, no threshold, no sample size and no time window are stated anywhere.** Anyone quoting a percentage or a rolling window is not quoting Meta.

**Automatic pausing.** S3 is unusually precise. A template is paused when it reaches the lowest quality rating — `RED` / "Active - Low quality" — and the durations escalate:

| Instance | Consequence | `other_info.title` on the webhook (S8) |
|---|---|---|
| 1st | paused for **3 hours** | `FIRST_PAUSE` |
| 2nd | paused for **6 hours** | `SECOND_PAUSE` |
| 3rd | **disabled** | `DISABLED` |
| (pacing) | paused pending quality assessment | `RATE_LIMITING_PAUSE` |
| (recovery) | unpaused | `UNPAUSE` |

A paused template cannot be sent; S3 states that attempts are not charged and do not count against the messaging limit, but the API rejects them. A pause does **not** initially affect the business phone number, and other high-quality templates keep sending — but S3 warns that a business that consistently sends templates which reach low quality may eventually see the phone number affected. Pauses and reactivations trigger a WhatsApp Manager notification, an email, and `message_template_status_update`.

**Recovery** (S3, in Meta's own order): halt campaigns using the template; wait for automatic unpausing, after which the template returns to Active and **its quality rating resets based on the most recent customer feedback**; or unpause manually — required for templates paused by Template Pacing — with `POST /{whats_app_message_template_id}/unpause` or the "manually unpause it" link in WhatsApp Manager; or edit and resubmit the template, which returns it to In Review until re-approved; or adjust business logic such as targeting and delivery parameters; or appeal a rejection with a sample, decided within 24 hours.

### 2.7 Template pacing — the second, distinct pause

S7 documents a pause that has nothing to do with accumulated quality history. Pacing exists to give customers time to give early feedback before a template reaches a large audience. It applies to **marketing and utility** templates, specifically newly created templates, previously paused templates that have been unpaused, and older templates without a `GREEN` quality rating. Utility templates are paced **only if you have already had a utility template paused**, and then for the **next 7 days**.

Mechanically: messages send normally until an undisclosed threshold, after which messages are **held** while feedback is gathered. The send response carries `message_status` of either `accepted` or `held_for_quality_assessment` (S7 states this appears on all API versions). On positive feedback the held messages are released to the full audience. On negative feedback the held messages are **dropped**, the template status becomes `PAUSED`, a `message_template_status_update` fires with event value `paused`, each held message produces a `messages` webhook with `"status":"failed"` and code `132015` (Cloud API), a `message_template_quality_update` fires, and admins are notified via Meta Business Suite, a WhatsApp Manager banner and email. Meta states a guardrail: even when paced, high-throughput campaign messages should be delivered within an hour at the 99th percentile, and if the guardrail is reached before a quality decision the held messages are released normally.

The practical consequence for Lynomia: a campaign can report `accepted` and then fail wholesale minutes later, and the distinguishing signal available at send time is `message_status: held_for_quality_assessment`.

### 2.8 Category re-classification after approval

This is the single most operationally dangerous area in scope, because it changes an **already approved** template without the business doing anything. All of the following is from S5.

**At creation**, WhatsApp validates the chosen category against the content: `APPROVED` if it agrees, `PENDING` while reviewing, `REJECTED` with `reason` `INCORRECT_CATEGORY` if it disagrees. **Since April 9, 2025**, a template submitted as `UTILITY` that WhatsApp considers `MARKETING` is **approved as `MARKETING`** rather than rejected.

**After approval**, a recurring reclassification process — begun **July 1, 2024** — can move categories:

| Change | Notice | Effect on the template |
|---|---|---|
| Utility → marketing | Normally **1 day** advance notice. **From April 16, 2025**, a business that has received a misuse warning gets **no notice** and the change is **instant**. | Status stays `APPROVED`; only the category (and therefore the price) changes |
| Marketing or utility → authentication | Advance notice is given. Process began **October 1, 2024**. | On the **first day of the following month** the template is set to **`REJECTED`** and can no longer send messages |

**How a business sees it coming.** Advance notice arrives by email, a WhatsApp Manager banner or CSV, Business Support, and the `template_category_update` webhook, which carries `correct_category`, `new_category`, and — for the post-change notice — `previous_category`. Via the API, request `category,correct_category` from the message templates endpoint: equal values mean the change has already happened; a mismatch with a non-empty `correct_category` means the change lands on the first day of next month; an empty or null `correct_category` means the template is unaffected.

**Misuse enforcement ladder** (S5), reported by an `account_update` webhook with violation types such as `UTILITY_TEMPLATE_ABUSE`, plus email:

| Level | What it does | Duration |
|---|---|---|
| Warning | Sent to WABA admins; from then on, utility→marketing changes are instant | — |
| Rate limiting | Utility messages capped in a rolling 24-hour window | at least **7 days** |
| Utility restriction | Approved utility templates become `MARKETING`; new utility templates and category reviews are disabled | **7 days**, or **30 days** for repeat violations |
| Portfolio-level restriction | Applies across all WABAs under the same Business Suite | **30 days** |

### 2.9 Editing, and which statuses allow it

S6: only `APPROVED`, `REJECTED` or `PAUSED` templates can be edited. An approved template can be edited **up to 10 times in a 30-day window, or once in a 24-hour window**. Rejected and paused templates have **no edit limit**. The category of an approved template cannot be changed. An edit replaces **all** components in the request — individual components cannot be edited. Editing a paused template causes the API to re-approve it automatically unless it fails review.

### 2.10 The webhooks

`message_template_status_update` (S8), object `whatsapp_business_account`, delivers `event`, `message_template_id` (integer), `message_template_name`, `message_template_language` (language-and-locale, e.g. `en-US`), `message_template_category` (`MARKETING` | `UTILITY` | `AUTHENTICATION`), `reason` (or `null` when the template is scheduled for deletion), and three conditional objects: `disable_info.disable_date` (a Unix timestamp, only for disabled templates), `other_info.title` + `other_info.description` (pause/unpause detail), and `rejection_info.reason` + `rejection_info.recommendation` (**only** for `INVALID_FORMAT` rejections).

`message_template_quality_update` (S9) delivers `previous_quality_score` and `new_quality_score` — both drawn from `GREEN` | `YELLOW` | `RED` | `UNKNOWN` — plus `message_template_id`, `message_template_name` and `message_template_language`.

A third, `template_category_update`, carries `correct_category`, `new_category` and `previous_category` (S5). S11 also lists `message_template_components_update` as a fourth template webhook; I did not read it, and it is adjacent to agent 009's scope.

**Neither webhook is sufficient on its own.** S1 is explicit that status changes are communicated via `message_template_status_update` *but* that the Template API `status` field can be requested at any time to get the current status — i.e. Meta expects reconciliation, not webhook-only state.

---

## 3. Error codes and failures

Only codes a source states. Meta's own titles for these codes do not appear on any page read, so the title cells are `not stated` rather than guessed — agent 005/011 should fill them from the error-codes reference.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| `132015` | not stated | not stated | Cloud API: attempt to send a **paused** template (v17.0 and later). Also the code on each held message that fails when a paced template is paused. | Halt sends; wait for auto-unpause, unpause manually, or edit and resubmit | Nothing — the message is not delivered | S7 (normative), S10 |
| `132016` | not stated | not stated | Cloud API: attempt to send a **disabled** template (v17.0 and later) | Edit and resubmit the template | Nothing | S10 |
| `132001` | not stated | not stated | The code returned for paused **and** disabled templates **before** v17.0 | Move off pre-v17 versions | Nothing | S10 |
| `2061` | not stated | not stated | On-Premises API: paused template | as above | Nothing | S10 |
| `2062` | not stated | not stated | On-Premises API: disabled template | as above | Nothing | S10 |

Non-code failure signals in scope: `message_status: held_for_quality_assessment` on the send response (S7); `messages` webhook `"status":"failed"` for each dropped held message (S7); `reason: null` on a `PENDING_DELETION` status webhook (S8).

---

## 4. Limits and numbers

| Number | What it governs | Source |
|---|---|---|
| up to **24 hours** | Template review decision | S1, S2 |
| within **24 hours** | Appeal decision | S2, S3 |
| **3 hours** | First automatic pause | S3 |
| **6 hours** | Second automatic pause | S3 |
| **3rd** instance | Template is disabled (not a longer pause) | S3 |
| **10** edits per **30** days; **1** per **24** hours | Editing an `APPROVED` template | S6 |
| no limit | Editing a `REJECTED` or `PAUSED` template | S6 |
| **60 days** | Window to request a category review/appeal in Business Support Home, and from creation or category-update date for approved templates | S5 |
| **1 day** | Normal advance notice before utility→marketing reclassification (zero for a business with a misuse warning, from 2025-04-16) | S5 |
| first day of the following month | When a marketing/utility→authentication reclassification sets the template to `REJECTED` | S5 |
| **7 days** | Window during which utility templates are paced after you have had a utility template paused | S7 |
| rolling **24-hour** window, **≥7 days** | Utility rate-limiting enforcement level | S5 |
| **7 days**, or **30 days** for repeat violations | Utility restriction enforcement level | S5 |
| **30 days** | Portfolio-level restriction across all WABAs in the Business Suite | S5 |
| **30 days** | Delivery attempts continue for a `PENDING_DELETION` template | S6 |
| **12 months** inactivity → archived; **28 days** later → deleted unless unarchived | Template archival | S1 |
| within **1 hour** at the **99th percentile** | Pacing guardrail for high-throughput campaign messages | S7 |
| **512** characters; **100** templates/hour; **250** per WABA unverified; **6,000** verified with approved display name | Creation-side limits — **agent 009's scope**, recorded only because they appear on S1 and constrain remediation | S1 |

No source read states a quality-rating threshold, percentage, sample size or evaluation window, or the pacing threshold. Those numbers do not exist in Meta's public documentation.

---

## 5. Version and deprecation notes

All from S10 (observational per program §6.2), cross-checked against S5 and S7 where possible.

| Date | Version context | Change |
|---|---|---|
| 2022-11-22 | Webhooks | `PENDING_DELETION` added to `message_template_status_update` events |
| 2023-02-02 | Graph API **v16.0** | Templates created or edited with v16.0 must use `AUTHENTICATION`, `MARKETING` or `UTILITY`; other categories unsupported |
| 2023-03-17 | Business Management API | `template_category_update` webhook field added; create/edit responses begin including status and category |
| 2023-04-04 | category validation applies to **v16.0+** | First category migration completed; category validation became part of review; `allow_category_change` added to create; **`INCORRECT_CATEGORY` added as a webhook `reason` value**; `previous_category` added to message templates |
| 2023-05-01 | Business Management API, all versions | All templates must be categorized `AUTHENTICATION` / `MARKETING` / `UTILITY` |
| 2023-05-23 | Cloud API **v17.0+** | Paused template send → `132015` (was `132001`); disabled template send → `132016` (was `132001`); On-Prem: `2061` paused, `2062` disabled |
| 2023-09-12 / 2023-10-12 | — | Unpausing rolled out to Brazil, Colombia and Singapore, then to all businesses (S3) |
| 2024-06-01 | Business Management API | Automatic category updates for miscategorized templates introduced |
| 2024-07-01 | — | Recurring post-approval reclassification process begins (S5) |
| 2024-10-01 | — | Marketing/utility→authentication reclassification process begins (S5) |
| 2025-04-09 | — | `allow_category_change` **no longer supported** at creation; reclassifying to `MARKETING` is now default behaviour. A `UTILITY` submission Meta reads as `MARKETING` is approved as `MARKETING` instead of rejected (S5) |
| 2025-04-16 | — | Businesses with a misuse warning get **no** advance notice on utility→marketing changes (S5) |
| — | — | `CATEGORY_NOT_AVAILABLE` marked **deprecated** in the `reason` enum (S8) |

The changelog contains **no** entry for `message_template_quality_update` or for any change to quality rating, pausing durations or disabling.

---

## 6. Ambiguities and gaps in Meta's documentation

1. **No reason-to-trigger mapping.** `ABUSIVE_CONTENT`, `SCAM`, `PROMOTIONAL` and `TAG_CONTENT_MISMATCH` appear only as enum members (S8). No page read defines them, and S2's prose list of rejection triggers is never tied to an enum value. Any mapping Lynomia publishes is an inference and must be labelled as one.
2. **`TAG_CONTENT_MISMATCH` is undefined** anywhere I could reach — not even a prose gloss.
3. **Four webhook events have no documented meaning**: `FLAGGED`, `LOCKED`, `LIMIT_EXCEEDED`, `REINSTATED`. A Lynomia webhook handler can receive all four.
4. **`other_info` is self-contradictory in S8**: described as appearing "for locked or unlocked templates", yet its documented `title` values are `FIRST_PAUSE`, `SECOND_PAUSE`, `RATE_LIMITING_PAUSE`, `UNPAUSE`, `DISABLED` — all pause-related. Which event populates it is unresolved.
5. **The disabled status has no stated API enum.** The webhook event is `DISABLED`; S6 only says "templates in a disabled status cannot be deleted".
6. **Webhook-only values vs the `status` field.** It is not stated whether `status` can ever return `IN_APPEAL`, `FLAGGED`, `LOCKED` or `LIMIT_EXCEEDED`, nor whether `status` filtering accepts them.
7. **Contradiction on editing a disabled template.** S2 says an approved template that became disabled should be edited and resubmitted; S3 implies the same; but S6 states that **only** `APPROVED`, `REJECTED` or `PAUSED` templates can be edited. Either S6's list is incomplete or S2's advice requires an intermediate step. **This needs arbitration before Lynomia documents a recovery path for a disabled template.**
8. **No quality formula, threshold, window or sample size** (S4). Also no definition of "low read-rate" and no statement of what counts as negative feedback (block? report? both? at what count?).
9. **"Negative feedback from multiple customers"** is the only quantifier given, for both `YELLOW` and `RED` (S1, S4) — the two levels are described with identical causes and differ only in stated risk.
10. **Pause-instance counter scope and decay are unstated.** S3 says the rating "resets based on the most recent customer feedback" after an unpause, but does not say whether the 1st/2nd/3rd pause counter ever resets. Whether a template can be paused twice, improve for a year, and still be disabled on the next pause is unknown.
11. **The pacing threshold is undisclosed** (S7), so no one can predict when holding starts.
12. **No API appeal endpoint is documented.** Content appeals and category reviews are described as WhatsApp Manager / Business Support flows only. `POST /{template_id}/unpause` is the only template-lifecycle action endpoint found outside create/edit/delete.
13. **`INCORRECT_CATEGORY` reachability after 2025-04-09** is unclear: S5 both states that a category disagreement produces `REJECTED` + `INCORRECT_CATEGORY`, and that the specific utility→marketing disagreement is now auto-approved as marketing. Which category pairs still reject is not stated.
14. **Body character limit "varies by format and tag"** and "emoji counts may be capped" (S2) with no numbers — a documented limit with no documented value.

---

## 7. What Lynomia users would ask

- "I submitted a template yesterday and it still says pending — is it stuck?" (≤24 hours, S2)
- "My template was rejected and the only thing I was told is `INVALID_FORMAT`. What is wrong with it?" (the `rejection_info.recommendation` field is the only machine-readable guidance Meta gives, and only for this reason — S8)
- "Why was my template rejected when I copied our existing one?" (duplicate body+footer wording, S2)
- "Why can't I send this template any more? It was approved last week." (paused, disabled, or reclassified to authentication and set to `REJECTED` — S3, S5)
- "How long is my template paused for, and do I have to do anything?" (3h / 6h / disabled; auto-unpause except after pacing — S3)
- "My campaign said it was accepted and then every message failed." (pacing: `held_for_quality_assessment` then `132015` — S7)
- "Why did my utility template suddenly become marketing, and why is my bill higher?" (post-approval reclassification, 1-day notice or none — S5)
- "My template says Medium quality. What did customers complain about?" (Meta does not disclose it; only the aggregate rating — S4)
- "Can I appeal? How?" (WhatsApp Manager only, must attach a sample, 24h decision; category reviews are a separate flow with a 60-day window — S2, S5)
- "I edited my approved template and now it won't let me edit again." (10 per 30 days, 1 per 24 hours — S6)
- "Will a paused template get my number banned?" (not initially; consistent low quality may eventually affect the number — S3)

---

## 8. Practical guidance — Meta's rules, separated from folklore

### 8.1 Getting approved — every item below is stated by Meta

| Practice | Source |
|---|---|
| Provide sample values for **every** variable, including media and text, at creation and again on any appeal | S2 |
| Get parameter syntax right: matched curly braces, sequential numbering, no `#`/`$`/`%`-style special characters, enough body text for the number of parameters, and never start or end the template with a parameter | S2 |
| Never request full card numbers, full financial account numbers or national ID numbers; partial identifiers are permitted | S2 |
| No abusive or threatening content, including threats of legal action and public shaming | S2 |
| Do not resubmit a body+footer wording that duplicates an existing template — except for `AUTHENTICATION` templates, which are exempt from the duplicate check | S2 |
| Choose the category honestly: utility must be non-promotional and either tied to the user's request/account or essential to the user (e.g. safety alerts); authentication must use a Template Library template with a one-time-password button and must not contain URLs, media or emojis | S5 |
| Expect a decision within 24 hours and build the workflow around the `message_template_status_update` webhook rather than polling alone — while still reconciling against the API `status` field | S1, S2, S8 |

### 8.2 Staying approved — every item below is stated by Meta

| Practice | Source |
|---|---|
| Treat `YELLOW` as an alarm, not a warning light: Meta says to address the issues customers are reporting *before* a pause | S1, S4 |
| Subscribe to all three template webhooks — `message_template_status_update`, `message_template_quality_update`, `template_category_update` — because each reports a different failure mode | S8, S9, S5 |
| Poll `category,correct_category` to detect a pending reclassification: a mismatch with a non-empty `correct_category` means the change lands on the first of next month | S5 |
| On a pause, halt campaigns that use that template immediately — the API rejects the sends | S3 |
| Remember a pacing pause requires a **manual** unpause (`POST /{template_id}/unpause`), unlike a quality pause which lifts itself | S3 |
| Fix targeting and delivery logic, not just wording: Meta names business logic as a cause of negative feedback and low engagement | S3 |
| Use the 60-day category review window; it is the only appeal route for a utility→marketing change, and a successful review prevents the change | S5 |
| Avoid a misuse warning: after one, utility→marketing reclassifications become instant and unannounced | S5 |
| Budget edits: 10 per 30 days on an approved template, 1 per 24 hours — do not burn them on experiments | S6 |

### 8.3 Folklore — widely repeated and **not** on any Meta page I could read

Each of these is **observational, unconfirmed**. Lynomia documentation must either omit them or label them as community practice, never present them as Meta's rules.

| Claim | Status |
|---|---|
| "Avoid ALL CAPS" | observational-unconfirmed. Not on any page read. S2 mentions only a body character limit and an emoji cap, both without numbers. |
| "Maximum N emojis" | observational-unconfirmed as a number. S2 says emoji counts "may be capped" and states no value. |
| "A pause is 3 hours, then 6 hours, then 24 hours" | **contradicted by Meta**: the third instance is **disabling**, not a 24-hour pause (S3). |
| "Rename a rejected template before resubmitting, the name is burned" | observational-unconfirmed. S2's duplicate rule is about **body and footer wording**, not the name. |
| "Quality rating is a 7-day block-rate" / any specific percentage threshold | observational-unconfirmed. No window, signal weighting or threshold is published (S4). |
| "Delete and recreate the template to reset quality" | observational-unconfirmed, and risky: S6 says a sent-but-undelivered template's deletion produces `PENDING_DELETION` with 30 days of delivery attempts, and disabled templates cannot be deleted at all. |
| "Authentication templates are approved in minutes" | observational-unconfirmed. Meta states only "up to 24 hours" for all templates (S2). |
| "Three rejections suspend your WABA" | observational-unconfirmed. The only documented enforcement ladder is the utility-misuse ladder in S5, which is not triggered by rejections. |
| "Submitting at a particular time of day gets a human reviewer" | observational-unconfirmed. S2 says review is automated systems **and** manual review, with no scheduling detail. |
| "Appealing always works / appeals are pointless" | both unconfirmed. Meta states a 24-hour decision and nothing about outcome rates (S2). |
