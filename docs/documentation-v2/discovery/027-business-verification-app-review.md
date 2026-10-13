---
agent: 027
scope: The Meta approval layer — business verification, App Review, advanced access, Access Verification / Tech Provider & Solution Partner programmes, app modes, Official Business Account, and the data-handling reviews that gate access — and the operator/customer responsibility split
confidence: high
sources_normative: 13
sources_observational: 3
---

## 1. Source register

All rows checked **2026-10-13**. Every claim later in this report references a row by `[Sn]`.

| # | Source URL | Page title | Product | API/version context | Normative? |
|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/graph-api/overview/access-levels | Access Levels | Graph API | No version stated; rules are platform-wide, not version-scoped | Normative |
| S2 | https://developers.facebook.com/docs/development/release/business-verification | Business Verification | Graph API / App development | None stated | Normative |
| S3 | https://developers.facebook.com/docs/app-review | App Review | Graph API / App development | None stated | Normative |
| S4 | https://developers.facebook.com/documentation/resp-plat-initiatives/individual-processes/app-review/submission-guide | App Review — Best Practices / Submission Guide | Graph API / App development | None stated | Normative |
| S5 | https://developers.facebook.com/docs/development/release/access-verification | Access Verification | Graph API / App development | None stated | Normative |
| S6 | https://developers.facebook.com/docs/development/build-and-test/app-modes | App Modes | Graph API / App development | None stated | Normative |
| S7 | https://developers.facebook.com/docs/development/maintaining-data-access/data-use-checkup | Data Use Checkup | Graph API / Platform compliance | Data-handling questions added "Beginning January 2024" | Normative |
| S8 | https://developers.facebook.com/docs/development/maintaining-data-access/data-protection-assessment | Data Protection Assessment | Graph API / Platform compliance | None stated | Normative |
| S9 | https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/overview | Solution Partner (Solution Providers overview) | WhatsApp Business Platform | None stated | Normative |
| S10 | https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers | Become a Tech Provider | WhatsApp Business Platform | None stated | Normative |
| S11 | https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/app-review | WhatsApp app review | WhatsApp Business Platform | None stated | Normative |
| S12 | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/ | Embedded Signup | WhatsApp Business Platform (Cloud API) | Cloud API only for number registration | Normative |
| S13 | https://developers.facebook.com/documentation/business-messaging/whatsapp/official-business-accounts/ | Official Business Accounts | WhatsApp Business Platform | OBA Status API field `official_business_account` | Normative |
| S14 | https://www.facebook.com/business/help/2058515294227817 | Verify Your Business in Meta Business Suite | Business Help | n/a | Normative domain, **body not retrievable** (JS-rendered; fetch returned title only) |
| S15 | https://www.facebook.com/business/help/193400874040813 | Which Documents are Required for Incorporated and/or Registered Business Entities | Business Help | n/a | Normative domain, **body not retrievable** (same) |
| S16 | https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/access-verification | (path only — page returned chrome/nav, no body) | WhatsApp Business Platform | n/a | **Not retrievable** |
| O1 | Search-result summary over S14/S15 and https://www.facebook.com/business/help/497330474385146 (Submitting Documentation for Organization Confirmation) | — | Business Help | n/a | **Observational, unconfirmed** — summarised, not read on-page |
| O2 | Search-result summary citing the Tech Provider page stating access verification is "no longer required to become a Tech Provider" | — | WhatsApp Business Platform | n/a | **Observational, unconfirmed** — not found in the on-page text of S10 |
| O3 | Search-result summary of https://developers.facebook.com/community/threads/641454991292066/ (forum answer on becoming a BSP) | — | Developer Community Forum | n/a | **Observational, unconfirmed** — forum, explicitly non-authoritative |

Three normative pages (S14, S15, S16) could not be read. Everything in this report about **which documents Meta accepts** therefore rests on O1 and is marked unconfirmed. That is the single largest hole in this area and it is precisely the question customers ask first.

## 2. The rules

### 2.1 Access levels are the spine everything else hangs off

Meta does not gate capability primarily by "approved / not approved". It gates by **access level per permission** [S1].

- **Standard Access**: "Permissions with Standard Access can only be requested from app users who have a role on the requesting app." Business, Consumer and Gaming apps are auto-approved for Standard Access on every permission available to their app type [S1]. This is development-grade access: enough to call an endpoint against your own assets, never enough to serve a customer.
- **Advanced Access**: "Apps can request permissions with Advanced Access from any app user, and features with Advanced Access are active for all app users." It "must be approved on an individual permission and feature basis through the App Review process" [S1].

Two statements on S1 are load-bearing for Lynomia: **"Business Verification is required to get Advanced Access"**, and apps with Advanced Access must complete the annual Data Use Checkup. Downgrading a permission from Advanced to Standard "will invalidate/deactivate any permission/feature" — so the downgrade is not a safe experiment [S1].

### 2.2 Business Verification

Business Verification is the process by which Meta "gather[s] information about you and your Business" to establish that the business is real and that the person acting is connected to it [S2].

Who must do it [S2]: any app that needs advanced access to permissions, **or** that lets other businesses access their own data, must be connected to a Business that has completed Business Verification. An app used only by people who hold a role on the app itself is exempt — "you do not need to complete verification."

What is blocked without it [S2]: "app users from other Businesses will be unable to grant these apps" the permissions, and "all features will be inactive." For WhatsApp specifically, "Your business must be verified before you can start the app review process" [S10] — so verification is not parallel to App Review, it is a precondition.

Mechanics [S2]: App Dashboard → Settings → Basic → Verification → Start Verification. An app can be connected to a Business you administer whether or not that Business is verified; if it is already verified, connecting finishes the process. If it is not, the flow hands off to Business Manager, where "the verification process itself must be completed."

The role split inside this step is a real operational trap: "anyone with an Administrator role on your app can connect it to a Business," but "only someone with an Admin role in the Business will be able to complete the verification process" [S2]. A developer can get the app 80% of the way and then be unable to finish.

Submission content, per the WhatsApp onboarding flow [S10]: business name, address, phone number, email and website; plus confirmation of your connection to the business through a contact method you select; plus document upload "if your business isn't found."

**Documents.** S2 does not list them — it defers to the Business Manager Help Center. S14 and S15, the pages that do list them, would not render. From O1 (*observational, unconfirmed*): the legal business name, address, phone and website must match the legal entity exactly; where Meta cannot auto-confirm, accepted evidence includes a certificate of formation or incorporation / business charter / company registration form, a tax-ID document (an IRS EIN assignment letter or IRS-stamped federal business tax return in the US), and proof of identity for owners at or above 10% ownership; utility bills, invoices, website printouts and self-completed forms are *not* accepted, and a Social Security Number is not accepted in place of an EIN. Requirements differ by country and by which verification flow you are in. **Do not ship this list in customer documentation as fact** — it needs a human to open S14/S15 in a browser and confirm.

**Timelines, rejection reasons and appeals.** Not stated on any normative page retrieved. S2, S10 and S4 are all silent on how long verification takes, why it is rejected, and how to appeal. This is the gap that produces "blocked for weeks with no explanation", and Meta's developer documentation genuinely does not answer it.

### 2.3 Access Verification — the step most providers do not know exists

This is the least-known gate and the one that most precisely describes Lynomia's position [S5].

Access Verification verifies "whether a business operates as a Tech Provider." Some Graph endpoints run a check when an app created or claimed by a business calls them: **if the person who granted the permission holds no role on the app, the endpoint checks whether the app's claimant business is a verified Tech Provider.** An unverified business gets **error code 100** [S5].

It is required, not optional: a business that has created or claimed an app used by other businesses and needs one of the **34 listed permissions** "must be verified as a Tech Provider before other businesses can use the app." S5 states this is **independent of App Review and of permission access levels** — passing App Review does not satisfy it [S5].

Prerequisites and steps [S5]: Business Verification first; the business account must carry no restrictions; then open the form from the notification email or App Dashboard → Basics → Verifications → Access verification; categorise and describe how the business uses other businesses' data to provide a service; wait. "A decision will be made within approximately 5 days." Existing businesses "will have 60 days to complete the verification process," after which the endpoint checks are applied gradually.

Status is lost if the business becomes unverified, the app is disconnected from the business, or the business account is restricted — and restored automatically when the condition is reversed [S5]. A single unrelated business-account restriction therefore silently breaks every customer's messaging.

### 2.4 App Review

App Review is required "if anyone without a role on the app, or a role in a Business that has claimed it, will use the app"; it is not required if only role-holders will use it [S3]. Meta tests the app to confirm it actually uses what was requested, and the consequences are blunt: "If we are unable to access your app to test it, your entire submission will be rejected" [S3]. If Meta can reach the app but not the specific feature, that item is not approved.

**Submission contents** [S4], in order:

1. App Review → Permissions and Features — select what you are requesting.
2. Business verification, prompted inline if incomplete.
3. Data handling questions, answered once business verification is approved; responses are "immediately evaluated and could take up to 30 seconds."
4. App settings: a **1024x1024** compliant app icon with no Meta trademarks or logos; a privacy policy URL (shown to users in Meta authentication interfaces); an app purpose — choose "Clients" rather than "Yourself or your own business" when other businesses will use the app; an accurate category; and a primary contact email you can actually read, because submission notifications go there.
5. App verification / access instructions: if users sign in via Meta authentication, say so and describe how reviewers reach the app. Reviewers use **their own** test accounts — "Do not provide your personal Meta Technologies app account credentials."
6. A per-permission written usage description plus a screen recording. "Each permission and feature must have its own description. Do not copy and paste."
7. Accept the Platform Onboarding Terms and submit. "Submissions in draft mode will not be reviewed" [S11].

A further prerequisite that catches people: make at least one successful API call per permission you are requesting advanced access for, "within 30 days of submitting for App Review" [S4]. You cannot get reviewed for a permission you have never exercised.

**Screencast requirements** [S4]: 1080p or better, monitor width 1440 or less; record full screen or only the app window and "record only what we need to see"; set the UI to English where possible and add captions/tool-tips where it is not self-explanatory; use the mouse and enlarge the cursor, because "If we can't see what you're doing, we can't test it!"; omit audio, reviewers will not listen; show an app user **granting** each permission and then the app **using** it. QuickTime or OBS are acceptable. Screenshots are not: "you cannot submit a screenshot, you must submit a screen recording" [S11].

**WhatsApp-specific review** [S11, S10]. The permissions to request are `whatsapp_business_messaging` (send messages, manage profiles and phone numbers) and `whatsapp_business_management` (access business assets); `whatsapp_business_manage_events` exists only for the Marketing Messages API with Conversions API and "is automatically approved if you already have Advanced access for whatsapp_business_messaging permission" [S11]. "If you are building an app that other businesses will be using, you must request Advanced access" [S11]. Two recordings are required and they must be separate: one showing a message created and sent from your app and received in a WhatsApp client, one showing a message template being created in your app or in WhatsApp Manager [S10]. "You must submit a different video clip for each permission" and "Do not submit a video that includes multiple permissions supporting different use cases" [S11]. Where you sit on top of a Solution Partner's API, "ask the Solution Partner to share a video with you that you can submit as part of your submission" [S11].

**Common rejection reasons**, all stated: requesting unnecessary permissions ("a common reason for rejection") [S11]; any requested item missing a screen recording [S4]; a recording that does not demonstrate the actions the permission is for [S4]; one video covering multiple permissions [S11]; a screenshot instead of a recording [S11]; copy-pasted descriptions [S4]; usage outside the permission's Allowed Usage section [S4]; an app reviewers cannot access [S3]; submitting personal account credentials [S4]; trademark/logo problems in the icon or name [S4]; no recent successful API calls [S4]; a submission left in draft [S11].

### 2.5 App modes

All newly created apps start in **Development mode** and "should stay there until development is finished" [S6].

| | Development mode | Live mode |
|---|---|---|
| Permissions | "Apps in Development mode can only request permissions from role users" | "Apps in Live mode can request permissions from anyone" — but only those approved through App Review |
| Features | Active only for role users | Only App-Review-approved features are active |
| Discoverability | Not findable through Facebook's tools and APIs; App Center listing hidden | Findable by anyone; App Center listing shown if eligible |
| Test data | Visible only to role users | "Test data becomes visible to all app users once the app switches to Live" |

Source: [S6]. Switching is a toggle in the App Dashboard toolbar, available to app administrators.

The timing rule is explicit: "You should only switch it to Live mode after you have completed app development and have completed App Review" [S6]. Going Live early is listed as a rejection-adjacent hazard in its own right — it "limits users to approved permissions and features, can make the app unusable for role-holders, and exposes Development-mode test data to all users" [S4].

For Embedded Signup the mode shows up directly in the customer's face: in development mode the authorization screen shows permissions only to admin, developer or tester roles; in live mode it shows only permissions approved through App Review [S12]. A customer who sees an empty or wrong consent screen is looking at an app-mode or App-Review problem, not a bug in the signup flow.

S6 does **not** mention a privacy policy URL requirement, business verification, webhook behaviour or test-user behaviour as conditions of going Live. The privacy policy URL requirement comes from the App Review submission path instead [S4]. Do not document a Live-mode prerequisite list that S6 does not state.

### 2.6 Tech Provider vs Solution Partner

| | Tech Provider | Solution Partner |
|---|---|---|
| Definition | "Tech Providers are similar to Solution Partners in that they also can offer a full range of WhatsApp Business Platform services" [S9] | "Solution Partners are Meta Business Partners that provide a full range of WhatsApp Business Platform services" [S9] |
| Meta Business Partner status | Not required [S9] | Required; S9 calls becoming one "a lengthy process" [S9] |
| Credit line | "Unlike Solution Partners, however, Tech Providers do not have credit lines" [S9] | "Solution Partners have credit lines which can be extended to clients who they bring on board" [S9] |
| Who pays Meta | Meta bills the client for API usage; the provider bills separately for its own services [S9] | The partner can "directly invoice their clients for the WhatsApp Business Platform services" [S9] |
| Client payment method | Client "must provide their own payment method after onboarding is complete" [S9]; clients "must add a payment method to their WhatsApp Business account" before messaging [S12] | Client can message immediately because the credit line is shared [S12] |
| Tokens | "Tech Providers should use business tokens exclusively" [S9] | System token "only when sharing your credit line with onboarded clients"; needs Admin or Financial Editor on the portfolio and `business_management` [S9, S12] |
| Partner-initiated WABA creation | No [S9] | Yes [S9] |
| Submitting verification on a client's behalf | No [S9] | Yes, for Select or Premier Solution Partners, with "a much faster turnaround time" [S9] |
| SMB Accelerator Program | "cannot participate ... unless they upgrade to a Tech Partner" [S9] | Eligible [S9] |

S9's own recommendation, quoted: if "you don't need a credit line and don't need to invoice your clients for API usage directly, consider becoming a Tech Provider instead."

The Tech Provider onboarding path itself is short [S10]: a Meta app with the WhatsApp use case and a connected business portfolio → business verification → App Review for advanced access on `whatsapp_business_messaging` and `whatsapp_business_management` → webhooks configured before any customer can send, receive or manage templates. "Confirmed Tech Providers have access to all support channels" [S10]. What it unlocks: providing WhatsApp messaging services to onboarded clients independently or jointly with a Solution Partner; onboarding via Embedded Signup; onboarding existing WhatsApp Business **app** users on their current account and number; sending on clients' behalf and reading their WABAs [S10].

"Business Solution Provider" (BSP) does not appear as a programme name on any page retrieved. S9 and S10 use **Solution Partner** and **Tech Provider**; S9 additionally references **Tech Partner** and the Meta Business Partner programme. The only source that uses "BSP" is a forum thread (O3, *observational, unconfirmed*), which claims the Meta Business Partner bar is very high and that only a small percentage are selected. **Treat "BSP" as legacy or colloquial vocabulary and do not use it in Lynomia documentation**; Meta's current taxonomy on the date checked is Tech Provider / Solution Partner / Tech Partner / Meta Business Partner.

### 2.7 Official Business Account — distinct from display-name approval

OBA is a separate, later, number-level status. All of these must hold [S13]: compliance with the WhatsApp Business Messaging Policy; the business "must be registered on the WhatsApp Business Platform for at least 30 days"; the owning business portfolio "has been verified through Business Verification"; the number "has enabled two-step verification"; and "the business phone number's display name has been approved." Meta also states: "We do not grant OBA status to business employees, test accounts, and WhatsApp Business app phone numbers" [S13].

Applying is an explicit act, not automatic: WhatsApp Manager → Overview → select the number → enable two-step verification if needed → Phone numbers → Profile → Official business account → **Submit Request**; or via the OBA Status API, requesting the `official_business_account` field, which returns an `oba_status` (the page's example value is `NOT_STARTED`) [S13].

**The badge is blue, not green.** S13: "Official Business Account business phone numbers have a blue checkmark beside their name in the contacts view." The brief's "green tick" framing does not match Meta's current wording; the only green checkmark in the retrieved material is a service-health indicator on the platform status page. Lynomia documentation should say *blue checkmark* and should probably say "verified badge" to survive the next rebrand.

The practical payoff S13 states is discoverability, not deliverability: "If a business phone number is not an Official Business Account (OBA), it will not appear in search results when users search for it within the WhatsApp application." S13 does **not** claim OBA raises messaging limits.

Denial: a rejection means the account "does not meet the eligibility requirements at this time," and "If your request is rejected, you can submit a new request after 30 days" [S13]. Profile fields stay editable and a denial does not restrict sharing business details.

The three things customers conflate — and the documentation must separate — are: (a) **Business Verification**, a portfolio-level identity check; (b) **display name approval**, a per-number review of the name shown to users, which S13 lists as an OBA prerequisite and which the display-name/phone-number pages own (agent 014's scope); and (c) **OBA**, an opt-in per-number badge that requires both of the above plus 30 days and two-step verification. None of the three implies another.

### 2.8 The data-handling reviews

| | Data Use Checkup (DUC) | Data Protection Assessment (DPA) |
|---|---|---|
| What | "an annual assessment that evaluates whether a developer's continued use of and access to specific data via Meta APIs is in compliance" [S7] | An annual **questionnaire** "designed to determine whether developers are complying with our Platform Terms" on how Platform Data is used, shared and protected [S8] |
| Who | An app admin, for apps live with a use case or holding advanced access to permissions or features [S7] | An app administrator, after enrolment; notified by email, Alert Inbox message and App Dashboard notifications [S8] |
| Trigger | Advanced Access is the main trigger. "Not required for apps with Standard Access" [S7] | Based on the app's access to "certain types of data"; S8 lists no specific permissions [S8] |
| Form | Review permissions/features/products, certify allowed use and compliance with Platform Terms and Developer Policies, answer data handling questions, provide testing instructions [S7] | A questionnaire, not a certification [S8] |
| Deadline | Not stated [S7] | "60 days to complete the assessment or risk losing platform access" [S8] |
| Consequence | Needed to "maintain API access"; S7 does not spell out the failure behaviour [S7] | Loss of platform access; also "Providing incomplete or vague answers may result in loss of platform access" [S8] |
| Relation to app mode | Development-mode apps don't need it yet but "will need to complete DUC before the app can be switched to Live mode" [S7] | Not stated |

Two things make these a documentation problem rather than a footnote. First, DUC is a **gate on going Live** [S7] — a Lynomia-style app cannot reach Live mode without it, which puts it on the critical path of first launch, not only of annual renewal. Second, both are annual and both are delivered to an **app admin's email**, so an unwatched inbox on Lynomia's side can revoke every customer's messaging at once. S8 explicitly positions both as backward-looking, against App Review which it describes as forward-looking.

## 3. Error codes and failures

Only two numeric codes appear on the retrieved normative pages for this layer. Both are approval-layer codes, and neither error text explains the approval problem that caused it — which is exactly the gap this agent was asked to cover.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 200 | not stated | not stated (referred to only as "error code 200") | The app called an endpoint using `whatsapp_business_management` against a WABA its own business does not own, without Advanced access. S10: "Without it, API calls that use this permission on WABAs not owned by your business return error code 200." | Nothing at the customer's end. The **provider** must obtain Advanced access for `whatsapp_business_management` through App Review | Nothing directly; symptom is that provider-side template or WABA management silently fails for that customer | S10, S11 |
| 100 | not stated | not stated (referred to only as "error code 100") | The Access Verification check failed: the permission was granted by someone with no role on the app, and the app's claimant business is not a verified Tech Provider | Nothing at the customer's end. The **provider's** business must complete Access Verification (~5 days) and must carry no account restrictions | Nothing directly; symptom is onboarding or sending breaking for every customer at once | S5 |

Business Verification rejection, App Review rejection, display-name rejection and OBA denial produce **no API error code** on any page retrieved. They arrive as dashboard state and email. Note also that `100` and `200` are generic Graph API code families — their meaning here is this layer's meaning, and agent 025's `OAuthException` work must not be allowed to overwrite it. Flagged for agent 028.

## 4. Limits and numbers

Every number below is stated by its cited source. Nothing is inferred.

| Number | What it governs | Source |
|---|---|---|
| 10 new business customers per rolling 7-day window | Default Embedded Signup onboarding limit; only newly onboarded customers count, and you get an email as you approach it | S12 |
| 200 new business customers per rolling 7-day window | The limit "after Business Verification, App Review, and Access Verification ... is automatically increased to 200" | S12 |
| Above 200 per week | "Apply to become a Meta Business Partner" | S12 |
| 34 | Permissions listed on S5 as subject to the Access Verification check | S5 |
| ~5 days | Access Verification decision: "a decision will be made within approximately 5 days" | S5 |
| 60 days | Access Verification: existing business admins "will have 60 days to complete the verification process" before checks are applied gradually | S5 |
| 60 days | Data Protection Assessment response window before risking loss of platform access | S8 |
| ~24 hours | "The average turnaround time for App Review is about 24 hours" (WhatsApp App Review page) | S11 |
| within a week | App Review decision expected within a week of submission (general submission guide) | S4 |
| 30 days | Window within which at least one successful API call per requested advanced-access permission must have been made before submitting | S4 |
| up to 30 seconds | Evaluation time for the App Review data handling answers | S4 |
| 1024x1024 | Required app icon size | S4 |
| 1080p or better; monitor width 1440 or less | Screen-recording quality requirements | S4 |
| 2 videos | Minimum for the WhatsApp Tech Provider App Review (one send, one template creation) | S10 |
| 30 days | Minimum WhatsApp Business Platform registration before OBA eligibility | S13 |
| 30 days | Wait before resubmitting after an OBA rejection | S13 |
| 2 | 555 test business phone numbers a customer may claim ("up to two") | S12 |
| 30 days | Embedded Signup sandbox account validity before deactivation and reclaim | S12 |
| 10% | *Observational, unconfirmed* — ownership threshold above which proof of identity is said to be required for business-verification documents | O1 |

S11's "about 24 hours" and S4's "within a week" are both stated for App Review and are not reconciled by either page. Document the range, not a single figure.

## 5. Version and deprecation notes

Little in this layer is Graph-version-scoped; it is account- and programme-scoped, which is why bumping an API version never fixes it.

- **February 16, 2021** — Business and Gaming apps created before this date were automatically approved for Advanced Access on `email` and `public_profile` plus anything already approved and in use through App Review [S1]. Apps created after it were not.
- **February 1, 2023** — from this date, apps requesting Advanced Access "may need to be connected to a verified business" [S1], and S2 repeats that advanced-access apps "might need to complete Business Verification." Note Meta's own hedging verbs here; see §6.
- **January 2024** — "Beginning January 2024," developers with live apps that have a use case or advanced access must also complete data handling questions as part of the annual Data Use Checkup [S7].
- **Documentation URL migration** — WhatsApp Business Platform pages have moved from `developers.facebook.com/docs/whatsapp/...` to `developers.facebook.com/documentation/business-messaging/whatsapp/...`, and App Review pages from `/docs/app-review/...` to `/documentation/resp-plat-initiatives/individual-processes/app-review/...`. Old `/docs/` paths still resolve (S2, S3, S5, S6, S7, S8 were read at `/docs/`). Any URL Lynomia hard-codes into help content should be re-checked, and the `/documentation/...` form preferred where it exists.
- **No API version** is stated by any page in this report. Treat all of §2 as version-independent unless a later agent finds otherwise.

## 6. Ambiguities and gaps

These are recorded, not resolved.

1. **Accepted documents for Business Verification are not established.** S2 defers to the Help Center; S14 and S15 would not render through a text fetch. The list in §2.2 is O1 and unconfirmed. Needed: a human opening S14 and S15 in a browser, per relevant country.
2. **No verification timeline, no rejection taxonomy, no appeal path.** No normative page retrieved states how long Business Verification takes, why it is rejected, or how to appeal. Meta documents the mechanics and not the outcomes. This is the real cause of "blocked for weeks" and Lynomia cannot document it away — it can only set expectations and tell the customer where to look.
3. **"Required" vs "might need".** S1 says flatly "Business Verification is required to get Advanced Access," then says apps "may need to be connected to a verified business" as of 2023-02-01; S2 says advanced-access apps "might need to complete Business Verification." S10 is unambiguous for WhatsApp ("must be verified before you can start the app review process"). For Lynomia's WhatsApp use case, treat it as hard-required. The general-platform hedge is unexplained.
4. **Is Access Verification required for a Tech Provider?** S5 says a business whose app is used by other businesses and needs one of the 34 permissions "must be verified as a Tech Provider," independent of App Review. S10's Tech Provider onboarding flow has **no** Access Verification step. S12 lists Access Verification as one of three things that raise the onboarding limit and says it does not state these are required to onboard at all. O2 (unconfirmed) claims the Tech Provider page says access verification is no longer required. **This contradiction must be arbitrated before any onboarding runbook is written** — it determines whether the critical path has three gates or four. Escalated to agent 000 / agent 028.
5. **App Review turnaround.** ~24 hours [S11] vs within a week [S4], unreconciled.
6. **Does the customer's own Business Verification block messaging, or only limits?** S9 says customers need business verification to be "eligible for increased messaging limits, business phone number limits, and Official Business Account status" — eligibility for *increases*, not permission to send. S12 says new customers start at standard messaging limits. No page retrieved says an unverified customer cannot message at all. Lynomia must not tell customers verification is required to send unless a later agent (014 / 018) finds a source saying so.
7. **DUC failure behaviour.** S7 says the checkup maintains API access but "doesn't specify what happens if the checkup isn't completed." No grace period stated, unlike the DPA's 60 days.
8. **DPA trigger.** S8 names no permissions and no criteria — "certain types of data." A provider cannot predict enrolment.
9. **OBA review time** is not stated [S13]; only "you will receive a notification once the request is reviewed."
10. **Display-name review mechanics** (statuses, rejection reasons, the `phone_number_name_update` webhook) are adjacent to OBA but belong to agent 014; this report establishes only that display-name approval is a distinct, per-number prerequisite of OBA [S13] and deliberately does not restate the status enums, which were seen only in search summaries here.
11. **Meta Business Partner / Solution Partner admission criteria** are not published on any page retrieved. S9 says only "a lengthy process." O3 is a forum post. Lynomia should not promise a customer or a reseller that Solution Partner status is attainable on a timeline.

## 7. What Lynomia users would ask

Questions this layer generates for the support desk, in roughly the order they arrive:

- "Why can't I connect WhatsApp — it says I need to verify my business. What do I upload?"
- "I submitted business verification. How long does it take?" (unanswerable from Meta's docs; §6.2)
- "My business verification was rejected and there's no reason given. What now?"
- "Do I need my own Facebook app / developer account?" (No. §8)
- "Do I need to do App Review?" (No, if onboarding through Lynomia. §8)
- "I'm in the signup flow and the Facebook screen doesn't ask for WhatsApp permissions." (Provider-side app mode or App Review. §2.5)
- "I connected successfully but I can't send a message." (Payment method on the customer's WABA, Tech Provider path. §2.6)
- "Why does another provider not ask me for a credit card?" (Solution Partner credit line vs Tech Provider. §2.6)
- "How do I get the blue tick?" (OBA: 30 days, verified portfolio, two-step verification, approved display name, then an explicit Submit Request. §2.7)
- "I was verified — why don't I have the tick?" (Verification ≠ display name approval ≠ OBA. §2.7)
- "My OBA request was denied." (No reason given; resubmit after 30 days. §2.7)
- "Can't I just use my personal name as the display name?" (Display-name policy; agent 014)
- "Everything broke at once for all my numbers." (Provider-side: Access Verification lost, business restriction, DUC/DPA lapse. §2.3, §2.8)
- "You onboarded my competitor last week but I'm stuck in a queue." (Rolling 7-day onboarding limit, 10 or 200. §4)
- "Does being verified raise my messaging limit?" (Eligibility for increases, not an automatic raise. §6.6)

## 8. Responsibility split — Lynomia operator vs customer business

Lynomia is a **Tech Provider** in Meta's taxonomy (or, if it ever obtains Meta Business Partner status and a credit line, a Solution Partner) [S9, S10]. Almost every approval that looks like a blocker is the **operator's**, done once; the customer's list is short, and the most common onboarding failure is sending a customer to do an operator's step.

### 8.1 Lynomia operator — once, for the whole platform

| Obligation | Blocked without it | Source |
|---|---|---|
| Meta app with the WhatsApp use case + connected business portfolio | Cannot begin | S10 |
| **Business Verification of Lynomia's own portfolio** (Business-level Admin required) | Cannot start App Review; non-role users cannot grant permissions; "all features will be inactive" | S2, S10 |
| **App Review → Advanced access** for `whatsapp_business_messaging` and `whatsapp_business_management` | Cannot onboard business customers at all; management calls on customer-owned WABAs return **error 200** | S10, S11, S12 |
| **Access Verification as a Tech Provider** (~5 days; business must carry no restrictions) | Endpoints return **error 100** when the granting user has no role on the app — i.e. for every real customer. *See §6.4: whether this is a hard gate or only a limit-raiser is unresolved* | S5, S12 |
| App settings for review: 1024x1024 icon, privacy policy URL, accurate category, app purpose = "Clients", a monitored primary contact email | Submission rejected | S4 |
| Per-permission written descriptions + separate screen recordings meeting the quality rules | Items without a recording "will not be approved" | S4, S11 |
| At least one successful API call per requested permission within 30 days before submitting | Not approved for that permission | S4 |
| Switch to **Live mode** only after App Review | Customer consent screen shows the wrong permissions or none; dev test data becomes visible | S4, S6, S12 |
| **Annual Data Use Checkup** (app admin) | Cannot switch to Live mode at all; API access not maintained | S7 |
| **Data Protection Assessment** within 60 days if enrolled | Risk of losing platform access | S8 |
| Keep the business portfolio unrestricted and the app connected to it | Access Verification status lost, automatically restored when reversed | S5 |
| Subscribe the app to webhooks on **each** onboarded customer's WABA | Customers cannot send, receive or manage templates | S10, S12 |
| Choose Tech Provider vs Solution Partner; if >200 new customers per 7 days is the plan, apply to become a Meta Business Partner | Onboarding throttled at 10 or 200 per rolling 7 days | S9, S12 |
| Use **business tokens exclusively** (Tech Provider) | — (S9 states it as the rule for the role) | S9 |

### 8.2 Customer business — per customer, per number

| Obligation | Blocked without it | Source |
|---|---|---|
| A Meta business portfolio and Facebook/Meta credentials; accept the terms shown in Embedded Signup | Cannot complete signup | S12 |
| Enter and verify a business phone number (their own, or one Lynomia provides), registered for **Cloud API** only | Cannot complete signup; numbers already on the WhatsApp Business app need a customised flow | S12 |
| Enter a display name — and then wait for Meta's approval | 555 test numbers cannot send without an approved display name; OBA ineligible | S12, S13 |
| **Add a payment method to their own WhatsApp Business account** (Tech Provider path) | Cannot message. Not required where a Solution Partner shares a credit line | S9, S12 |
| **Their own** Business Verification, of the portfolio that owns the number | Not eligible for increased messaging limits, increased phone-number limits, or OBA. *Not shown to block sending outright — §6.6* | S9, S13 |
| Enable **two-step verification** on the business phone number | OBA ineligible | S13 |
| 30 days registered on the WhatsApp Business Platform | OBA ineligible | S13 |
| Comply with the WhatsApp Business Messaging Policy | OBA ineligible; policy enforcement generally | S13 |
| Explicitly **Submit Request** for OBA in WhatsApp Manager (or via the OBA Status API) | No badge; the number will not appear in WhatsApp in-app search | S13 |
| Retains full WhatsApp Manager access, which Lynomia "cannot restrict" | — (a fact to state in onboarding, not a task) | S12 |

### 8.3 What the customer must NOT be asked to do

Each of these is a real wrong turn that a customer cannot complete, and documenting it as theirs sends them into a dead end:

- **Create a Meta developer app.** They do not have one; they use Lynomia's [S10, S12].
- **Submit App Review.** App Review is per app, and the app is Lynomia's [S3, S10].
- **Complete Access Verification / become a Tech Provider.** This verifies the business that *claims the app* [S5].
- **Complete the Data Use Checkup or Data Protection Assessment for Lynomia's app.** An app **admin** does these [S7, S8].
- **Switch an app to Live mode**, or interpret a thin consent screen as their own misconfiguration [S6, S12].
- **Expect OBA because they are verified.** Verification, display-name approval and OBA are three separate decisions [S13].
- **Expect Meta to bill through Lynomia** on the Tech Provider path — Meta bills them for API usage [S9].

### 8.4 Neither party decides

Business Verification outcomes, App Review outcomes, Access Verification outcomes, display-name approval and OBA grants are Meta's decisions. Only Access Verification (~5 days) and App Review (~24 hours / within a week) carry stated turnaround times; the rest do not, and none of Business Verification, display-name review or OBA publishes rejection reasons or an appeal route on any page retrieved here [S4, S5, S11, S13, §6.2]. Lynomia's onboarding documentation should say so plainly rather than inventing a timeline, because the invented timeline is what the support ticket will quote back.
