---
agent: 089
scope: Adversarial refutation of every WhatsApp claim in the 20 shipped corpus articles and in reports 001–020, 039, 040, 053, 054 — the 24-hour window, template rules and limits, opt-in and marketing, quality and tiers, coexistence, media, registration and display name, and every number
confidence: high
sources_normative: 14
sources_observational: 4
---

# Agent 089 — Refuting the WhatsApp claims

## 1. What you attacked

**The corpus.** All 20 shipped articles: `custom/db/documentation/en/whatsapp/{connect-whatsapp,
whatsapp-business-coexistence, the-whatsapp-24-hour-window, whatsapp-templates, whatsapp-template-lifecycle,
whatsapp-troubleshooting}.md` and `custom/db/documentation/en/whatsapp-errors/*.md` (14 files), with their Arabic
counterparts read for the same claims. Where a claim was also made in the product's own strings or code I attacked
both sides.

**The reports.** 001–020, 039, 040, 053, 054, as they stood at the time of writing.

**The method.** Every factual assertion was sorted into one of the three cases the brief names:

| Case | Meaning |
|---|---|
| **(a) current Meta position** | a page on `developers.facebook.com` states it today; the claim survives |
| **(b) stale or unsupported** | Meta's current page says something different, or no Meta page says it at all |
| **(c) Lynomia's behaviour presented as Meta's rule** | the claim is true of this product and false as a statement about WhatsApp |

Case (c) is the one this section of the corpus gets wrong most often, and it is the most damaging, because the
articles repeatedly open by telling the reader *"it is not a Lynomia Chat rule. It is WhatsApp's"*
(`the-whatsapp-24-hour-window.md:8-9`) and *"Meta owns these outcomes"* (`whatsapp-troubleshooting.md:11`). Those
sentences are load-bearing: they instruct the reader not to look for a Lynomia cause. Every case-(c) finding below
therefore sends a reader to Meta for something Lynomia did.

### 1.1 Source register

Date checked for every row: **2026-10-13**. All fetches were read-only `GET`s of public documentation. Nothing was
authenticated, no Graph endpoint was called, no form was submitted.

| Row | Source URL | Page title | Product | API / version context | Normative? |
|---|---|---|---|---|---|
| N1 | `developers.facebook.com/docs/whatsapp/cloud-api/guides/send-messages` | Service messages | WhatsApp Cloud API | examples `v25.0` | normative |
| N2 | `developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | Error codes | WhatsApp Cloud API | states `error_subcode` "Deprecated. Will not be returned in v16.0+ responses" | normative |
| N3 | `developers.facebook.com/docs/whatsapp/cloud-api/reference/media` | Media | WhatsApp Cloud API | examples `v25.0` | normative |
| N4 | `developers.facebook.com/docs/whatsapp/messaging-limits` and `/documentation/business-messaging/whatsapp/messaging-limits` | Messaging Limits | WhatsApp Business Platform | `max_daily_conversations_per_business` v24.0+; `max_daily_conversation_per_phone` v23.0 and older "until February 2026"; `messaging_limit_tier` deprecated | normative |
| N5 | `developers.facebook.com/docs/whatsapp/business-management-api/message-templates/components` | Template components | Business Management API | — | normative |
| N6 | `developers.facebook.com/documentation/business-messaging/whatsapp/templates/overview` | Template fundamentals | Business Management API | — | normative |
| N7 | `developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-management` | Template management | Business Management API | — | normative |
| N8 | `developers.facebook.com/docs/whatsapp/business-management-api/message-templates/` | Template fundamentals | Business Management API | — | normative |
| N9 | `developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/` | Onboard WhatsApp Business app users | Cloud API / Embedded Signup | page notes Embedded Signup v2 and v3 deprecate 2026-10-15 | normative |
| N10 | `developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/per-user-limits/` | Per-user marketing template message limits | WhatsApp Business Platform | — | normative |
| N11 | `developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers` | Business phone numbers | Cloud API | `name_status` "currently in beta and not available to all developers" | normative |
| N12 | `developers.facebook.com/documentation/business-messaging/whatsapp/support/health-status/` | Messaging and Calling Health Status | Cloud API | — | normative |
| N13 | `developers.facebook.com/docs/whatsapp/overview/getting-opt-in` | Getting opt-in | WhatsApp Business Platform policy | — | normative |
| N14 | `developers.facebook.com/docs/whatsapp/message-templates/guidelines` | Template fundamentals | Business Management API | — | normative |
| O1 | site-restricted search summaries of `facebook.com/business/help/896873687365001` | About Your WhatsApp Business Phone Number's Quality Rating | Business Help | — | **observational, not read directly** — the page served no body |
| O2 | site-restricted search summary asserting a limit decrease after 7 days Flagged | — | — | **observational, unconfirmed, and contradicted by N4's current text** |
| O3 | site-restricted search summary on template archival after 12 months and deletion 28 days after archiving | — | Business Management API | **observational, unconfirmed** |
| O4 | site-restricted search summary of `/documentation/business-messaging/whatsapp/marketing-messages/pricing/` (BETA) | Set a max price for marketing messages | WhatsApp Business Platform | **observational** — corroborates N7's content-edit caps and adds non-content-edit caps |

**Dead or unusable sources, recorded rather than guessed around.** `/docs/whatsapp/cloud-api/guides/coexistence`
returns **HTTP 404** — the coexistence guidance now lives under Embedded Signup (N9), so any citation the corpus or
a report stores to the old path is already broken. `facebook.com/business/help/338047025165344` (display-name
guidelines) and `/documentation/business-messaging/whatsapp/messages/opt-in` returned navigation chrome or a login
prompt with no body. The Graph API phone-number reference likewise returned navigation only, so **the normative
enumeration of `status` values could not be read** — see §4.

### 1.2 Timing audit: which Meta reports existed, and which did not

The brief said 001–028 were being written. At the time of writing, in scope:

| Present | Absent |
|---|---|
| 001, 002, 003, 004, 005, 006, 008, 009, 010, 011, 012, 013, 014, 016, 018, 019, 020 | **007** (webhook payload shapes), **015** (coexistence / migration / number porting), **017** (marketing limits, per-user caps, opt-in rules) |
| 039, 040, 054 | **053** (the `whatsapp` corpus section) |

That pattern matters more than the count. **Three of the eight areas the brief told me to attack had no
Meta-knowledge report at all**: opt-in and marketing claims (017), coexistence and migration claims (015), and the
webhook shapes (007) that the error articles depend on. And **053 is absent**, so the six `whatsapp/` articles —
the connect, coexistence, window, template, lifecycle and troubleshooting articles — had received no corpus-level
review from anyone before this one. 054 covered only `whatsapp-errors/`, and did so thoroughly; where I overlap it
I say so and I add the primary source it explicitly did not fetch (054:32: *"not re-fetched by me"*).

---

## 2. Refutations

Ordered by severity. Each gives the claim, who made it, why it is wrong, the evidence, the severity, and which of
the three cases it falls into.

### 2.1 `131053` is not a download failure. The article's whole premise is a code comment. — **blocker**, case (b)+(c)

**Claim.** *"`131053` means WhatsApp tried to **download a file from your installation and could not**. It is a
transport problem between Meta and whoever hosts your server, not a problem with the attachment."*
(`whatsapp-errors/whatsapp-error-131053.md:9-10`), with a causal story — *"Meta's download path is rate limited per
destination network, so on shared hosting your installation can be throttled because of traffic that has nothing
to do with you"* (`:19-22`) — and the operational advice that follows from it: *"Press **Retry** on the message.
Because the cause is intermittent, a retry genuinely can succeed here"* (`:37-38`).

**Why it is wrong.** N2, read live, gives 131053 as: Details — *"The media could not be uploaded for one or more
reasons, such as an unsupported media type."* Solution — *"Inspect any media files that are causing errors and
confirm that they are in fact supported."* N2 adds that the caller should check `error.error_data.details` on the
messages webhook and verify the file's MIME type with a tool such as `file -I`. This is a **send-side upload**
failure attributable to the file; Meta names no hosting, no network and no rate limit under this code. N1,
separately, discusses link-hosted versus id-hosted media and says only that *"the Cloud API internally caches the
asset for 10 minutes"* — **it does not mention rate limiting at all**.

The article's premise is traceable to two Lynomia source comments, not to Meta:
`app/services/whatsapp/providers/whatsapp_cloud_service.rb:191` (*"Referencing uploaded media by id avoids Meta's
fwdproxy download, which is rate limited per ASN (error 131053)"*) and
`app/services/whatsapp/media_upload_service.rb:5`. An internal engineering hypothesis was published as Meta's
definition of an error code.

**Consequence.** A user whose PNG was 8 MB, or whose `.ogg` was not OPUS-encoded, is told the problem is their
hosting provider, pointed at Account Health, and told to retry — and Meta's actual remedy, inspect the file and its
MIME type, appears nowhere in the corpus. Worse, the article's stated reason for keeping Retry (*"the cause is
intermittent"*) is the opposite of true for the documented cause: an unsupported media type fails identically every
time.

**Relation to 054.** 054 reached the same verdict through reports 005/019/020 (its G1/C4) and marked the article
REWRITE. I confirm it against the live page and correct one detail: 054's G1 quotes Meta's title as *"Unable to
upload the media used in the message."* The live N2 wording is the Details string above. Whoever rewrites should
quote N2, not 054's relayed title.

### 2.2 An unapproved display name *does* cost you something, and Meta publishes what. — **blocker**, case (b)

**Claim.** *"**Messages keep sending.** An unapproved display name does not block anything. What it changes is what
the customer sees: your number instead of your business name"* and *"A refusal is the least serious thing on that
page"* (`whatsapp-errors/whatsapp-display-name.md:9-16`). The article's Limits repeat it: *"A refused name does not
expire. The number keeps showing as a number until a name is approved"* (`:46`).

**Why it is wrong.** N12, Meta's Messaging and Calling Health Status page, defines `can_send_message` values
`AVAILABLE` / `LIMITED` / `BLOCKED` and gives, verbatim, as a reason for **LIMITED**: *"Your display name has not
been approved yet. **Your message limit will increase after the display name is approved.**"* So Meta's current
published position is that an unapproved display name places the number in a limited messaging state and holds its
message limit down. N4 points the same way: the 6,000-template ceiling is for *"verified portfolios with an
approved display name"*, against 250 for unverified.

The article is also incomplete in a way the product is not. N11 enumerates six `name_status` values —
`APPROVED`, `AVAILABLE_WITHOUT_REVIEW` (*"The display name is ready to use without review"*), `DECLINED`,
`PENDING_REVIEW`, `EXPIRED` (*"The phone number's certificate has expired and cannot be used to register the phone
number for API use"*) and `NONE` (*"The phone number does not have a certificate and cannot be used to register the
phone number for API use"*). Two of those six mean the number **cannot be registered for API use at all** — the
precise opposite of "does not block anything". Lynomia already renders five of them with their own copy
(`app/javascript/dashboard/routes/dashboard/settings/inbox/components/AccountHealth.vue:50-85`), and its own string
for `EXPIRED` says *"The phone number's certificate has expired, so this number cannot be registered for API use"*
(`app/javascript/dashboard/i18n/locale/en/inboxMgmt.json:996`). The article contradicts the product's own UI copy.

**Severity blocker** because the article's framing actively discourages the one action that lifts a messaging limit,
in a section whose sibling article tells the reader a tier increase *"is not something you can request"*
(`whatsapp-quality-and-limits.md:67`).

**Relation to 054.** 054 recorded these claims as *"partly; remainder unverifiable (Meta)"* (its F3). N12 makes
them verifiable and contradicted. 054's F3 should be upgraded.

### 2.3 The opt-in requirement is absent from the entire WhatsApp corpus. — **blocker**, case (b)

**Claim (by omission).** No article in `whatsapp/` or `whatsapp-errors/` states that Meta requires opt-in before a
business messages a WhatsApp user. The nearest thing is a **quality tip**: *"Send to people who asked. An audience
built from customers who opted in behaves completely differently from one built from every contact you have"*
(`whatsapp-quality-and-limits.md:40-42`). `audiences-and-campaigns/whatsapp-campaigns.md` — the article that
teaches a reader to send one template to every contact carrying a label — lists five prerequisites (`:29-35`) and
opt-in is not among them.

**Why it is wrong.** N1 states it twice, as a rule, not a tip: *"As a reminder, you can only send messages to
WhatsApp users who have opted in to receiving messages from you"* and *"Only send messages to WhatsApp users who
have opted into receiving messages from your business."* N13 gives the requirements: *"It is up to businesses to
determine the method of opt-in"*; opt-in may be general and *"not specifically for WhatsApp"*; businesses *"must
clearly state that a person is opting in to receive communication from the business"*, *"must clearly state the
business's name that a person is opting in to receive messages from"*, and *"must comply with applicable law."*

A policy obligation has been demoted to a deliverability optimisation, in a product whose campaign feature is built
for exactly the send that needs it. This is the single largest content gap in the section: the rules are short,
Meta publishes them plainly, they are easy to satisfy, and nothing in the corpus tells a Gulf retailer that a
purchased contact list is a policy violation rather than merely a weak audience.

### 2.4 The "24-hour window" failure message is Lynomia's own sentence, and Meta was never asked. — **major**, case (c)

**Claim.** *"If something sends a plain message anyway … that message does not quietly vanish. It appears in the
conversation marked **Failed to send**, with **WhatsApp's own explanation** underneath: the 24-hour customer
service window is closed and no template was used."* (`the-whatsapp-24-hour-window.md:46-48`), tabulated the same
way in `whatsapp-troubleshooting.md:42`.

**Why it is wrong.** `app/services/whatsapp/send_on_whatsapp_service.rb:15-17` returns before any Graph call when
`conversation.can_reply?` is false and writes
`external_error: I18n.t('errors.whatsapp.message_outside_messaging_window')`. That string is Lynomia's own English
copy, in `config/locales/en.yml:185`: *"Message not sent because the WhatsApp 24-hour customer service window is
closed and no template parameters were provided. Send an approved template message instead."* Meta is not
contacted, returns nothing, and says nothing. The product's own UAT record states the distinction as the key
diagnostic lever — a local refusal carries the window message and *"Meta never being contacted"*, a Meta refusal
carries `"131047: Re-engagement message"` (`docs/real-whatsapp-uat/06-delivery-status.md:83-90`).

Two further defects ride on the same two lines. The corpus **misquotes its own string** ("no template was used"
for "no template parameters were provided"), and it **never names 131047**, the code Meta publishes for the real
remote refusal, whose Details are *"More than 24 hours have passed since the recipient last replied to the sender
number"* and whose Solution is *"Send the recipient a template message instead"* (N2). A reader comparing the two
cases has no way to tell a Lynomia pre-emption from a Meta refusal, which is the first thing an operator needs.

### 2.5 "A hand-made token will expire again" is false, and contradicts the corpus's own setup instructions. — **major**, case (b)

**Claim.** *"**A token you generated by hand will expire again.** The guided sign-up is what avoids repeating
this."* (`whatsapp-errors/whatsapp-error-190.md:58`), repeated as *"A hand-made token will expire again. The guided
sign-up is what stops this recurring."* (`whatsapp-errors/whatsapp-reconnect-a-number.md:56`).

**Why it is wrong.** Meta offers a **non-expiring** system-user token. Report 002 cites Meta's own wording — tokens
that *"never expire and don't need refreshing"*, against a 60-day variant *"valid for 60 days from generation or
last refresh"* — and records Meta's qualification that long-lived tokens, *"This also applies to access tokens for
System Users in Business Manager"*, *"do not expire based on time, though they can be invalidated"*
(`docs/documentation-v2/discovery/002-system-users-permanent-tokens.md:185-190`). And the corpus's own connect
article instructs the administrator to generate exactly that kind: *"a permanent access token from a Meta system
user carrying both `whatsapp_business_management` and `whatsapp_business_messaging`"*
(`whatsapp/connect-whatsapp.md:45-46`).

So the corpus tells a reader to create a non-expiring token in one article and tells them in two others that the
token they created will expire. Error 190 on a correctly made permanent token means **invalidation** — revocation,
a removed permission, a changed app, a removed portfolio member, exactly the causes the 190 article's own opening
paragraph lists (`:9-11`) and its worked example dramatises (`:41-45`) — not elapsed time. Both Limits bullets
contradict the article they sit in, and both steer administrators away from a supported configuration on a false
premise.

### 2.6 Editing an approved template does not normally take it out of service. — **major**, case (b)

**Claim.** *"Saving a change to an approved template sends it back to WhatsApp for review. While it is in review it
may not be sendable, so a campaign or flow depending on it can stop working for a while."*
(`whatsapp-template-lifecycle.md:52-53`), with a worked example that states it as fact: *"The template now reads
**In review at WhatsApp**, and the flow's Send template node cannot use it while it is there, so it follows its
failure path"* (`:82-83`). The product's own warning says the same:
`app/javascript/dashboard/i18n/locale/en/whatsappTemplateMgmt.json:84`.

**Why it is wrong.** N7 states, verbatim: *"After you edit an approved or paused template, the API automatically
re-approves the template"* — *"unless it fails template review."* Meta's documented default is automatic
re-approval; loss of service is the exception, not the rule, and Meta attaches it to failing review rather than to
the review taking place. The article presents the exception as the normal outcome and builds its central worked
example on it.

The adjacent claims in the same article survive and should be kept (§3): the 1-per-24-hours and 10-per-30-days
caps, the editable-status list, the category lock on approved templates, and whole-template replacement.

### 2.7 The 30-day name block is narrower than the corpus says, and "in any language" is unsourced. — **major**, case (b)

**Claim.** *"Deleting a template **WhatsApp holds** is a real deletion at WhatsApp: … **WhatsApp blocks the name
for 30 days.** You cannot recreate `order_shipped` under that name for a month, **in any language**"*
(`whatsapp-template-lifecycle.md:67-72`).

**Why it is wrong, twice.** N7 scopes the block to approved templates: *"**If you delete an approved template**, you
cannot create a new template with the same name for 30 days."* The corpus applies it to every template WhatsApp
holds — including rejected, paused and in-review templates, for which N7 states no block. And **no source states
"in any language."** N8 says the opposite about name scope: template names are not unique, and several templates
may share a name in different languages, each counting separately against the template limit.

This also makes the corpus contradict itself. `whatsapp-templates.md:142` tells the reader *"A name has to be
unique **per language** within one business account — including a name WhatsApp is still holding from a template
you deleted in the last 30 days."* Per-language and "in any language" cannot both be right; N7 and N8 support the
per-language reading.

### 2.8 The copy-code cap is Lynomia's, the stated reason is false, and the repo already knows. — **major**, case (c)

**Claim.** *"**A copy-code sample is capped at 15 characters**, stricter than WhatsApp's own limit, **because a
longer coupon would fail at send time**."* (`whatsapp-templates.md:117-118`).

**Why it is wrong.** N5 gives the copy-code example string as *"Maximum 20 characters."* A 16–20 character coupon
would be accepted by Meta. It fails because **Lynomia raises on it**:
`app/services/whatsapp/populate_template_parameters_service.rb:20` —
`raise ArgumentError, 'Coupon code cannot exceed 15 characters' if coupon_code.length > 15`. The repository records
the drift explicitly: `custom/app/services/whatsapp/templates/validator.rb:16` reads *"Meta raised the coupon code
from 15 to 20 on 2025-12-03. Whatsapp::PopulateTemplateParametersService still refuses longer"*, with
`BUTTON_COPY_CODE_MAX = 15` on `:19` and `COPY_CODE_MAX = 15` in `custom/app/services/flows/template.rb:14`.

The first clause of the article's sentence is right and well scoped. The causal clause attributes a Lynomia
`ArgumentError` to WhatsApp's send path, which is case (c) in its purest form, and it does so about a number the
repository has already annotated as stale.

### 2.9 Quality rating is not about people not replying, and tiers do not fall when the rating is red. — **major**, case (b)

Three claims in `whatsapp-errors/whatsapp-quality-and-limits.md`:

| Claim | Why it is wrong |
|---|---|
| *"a rolling judgement based on how recipients react — blocking the number, reporting it, **or simply never replying**"* (`:14-16`) | No Meta page I read names non-reply as a quality-rating input. N11 points to the quality-rating help article for the definition and that page served no body (O1); the search summaries of it (O1) describe blocks, reports, mutes, archives and block reasons, i.e. **user feedback signals**, over a **7-day** window. Low read rate is a documented input to **template pausing** (N6/N14: *"paused due to recurring negative feedback from customers, or low read-rates"*), not to the number's quality rating. The article moves a template-level signal onto the number and invents the non-reply input |
| *"Tiers go up on their own when you send consistently at quality, and **down when the rating is red**"* (`:31-32`) | N4 documents **no decrease mechanism at all**. I searched its text for decrease, lower and Flagged and found only the increase criteria. One search summary asserts a one-level decrease after 7 days Flagged (O2) — unconfirmed, not read directly, and contradicted by the live page. Report 018 reached the same conclusion independently (`018-messaging-limits-tiers.md:95`, `:300`). A downgrade rule may well exist; **no retrievable Meta page states it**, so the corpus must not |
| *"Tiers go up **on their own**"* and *"A tier increase is not something you can request in the product"* (`:31`, `:67`) | Incomplete to the point of being misleading. N4 makes leaving 250 a **gated step with three alternative scaling paths**, one of which is **business verification** and another **partner verification**; the third is *"Send 2,000 delivered messages outside of customer service windows"* within a 30-day moving period using high-quality templates. Only *above* 2,000 is scaling automatic, and then it needs *"at least half of your current messaging limit"* used in the last 7 days. The most actionable fact in the whole area — verify the business — appears nowhere in the corpus |

Also absent, with sources available: the ladder itself (**250 / 2,000 / 10,000 / 100,000 / Unlimited**, N4) and the
7-day basis and 30-day history view for the rating (O1). The article states that the two numbers are "related but
not the same thing, and confusing them wastes effort" and then gives neither number's scale.

### 2.10 The "nobody here has met it" rule — adjudication of the assigned conflict. — **major**

**The two positions.** `whatsapp-troubleshooting.md:102-105`: *"Where WhatsApp's refusal begins with a number,
there is a page about that number. Those are the ones this installation has actually seen; **a code with no page
here is one nobody here has met**, and inventing an explanation for it would be worse than leaving it to WhatsApp's
own words."* Against it, report 040 concludes the article is *"not true as written: 131047 and 131026 were **met and
recorded** in `docs/real-whatsapp-uat/{05-outbound-new-contact,06-delivery-status}.md`"*
(`040-whatsapp-runtime.md:333-334`, restated `:170`, `:304-308`).

**The evidence.** I read every occurrence of both codes in that directory. There are six, and none is an
observation:

| Citation | What it actually is |
|---|---|
| `06-delivery-status.md:18` | a hand-written **example** JSON webhook body inside a fenced block illustrating where statuses arrive |
| `06-delivery-status.md:83-85` | prose **derived from the code**, explaining what `external_error` would contain, quoting the `update_message_with_status` snippet immediately above it |
| `05-outbound-new-contact.md:137` | a sentence about what *would* arrive, quoting Meta's own error text |
| `05-outbound-new-contact.md:171-172` | a classification table under the heading *"The outbound classification, **if the template test does fail**"* — explicitly contingent |
| `FINAL-CHECKPOINT.md:301` | the same code-derived string, illustrating local-versus-Meta failure |

And the directory's own results file closes the question: `docs/real-whatsapp-uat/10-real-uat-results.md:3` reads
**"Status: BLOCKED — REAL SERVER DIAGNOSIS REQUIRED"**, with four structural reasons — *"no real credential"*,
*"fixture identity"* (*"the local `business_account_id` and `phone_number_id` are factory values. Meta has no such
number"*), *"no handset"*, and *"not the callback destination"*. No real inbound or outbound message happened in
that phase at all.

**Verdict.** **Report 040's conflicting claim is refuted on its own citations.** 040 is internally inconsistent: at
`:156-157` it correctly classes both codes as *"Named in a design record and in fixtures only"*, and at `:333-334`
it upgrades "named in a design record" to "met and recorded". The second wording is the error and should be struck.

**But the article's sentence does not survive either, and this is the part that matters.** It is wrong in the
*other* direction: it claims observational provenance for all five code pages, and the classifier it appeals to
records only two. `custom/app/services/whatsapp/delivery_failure.rb:9-10` states *"Only codes this installation has
actually observed on its own traffic are classified"*, and its `CODES` map has exactly two entries — 131049 and
131042 (`:30-33`). The other three pages exist for structural reasons: 131053 rests on an upstream code comment
(§2.1), 131060 on a deliberate placeholder (`app/services/whatsapp/incoming_message_base_service.rb:93`), and 190
is a Graph-wide auth class surfaced by `Whatsapp::HealthService::ApiError#authorization_error?`
(`app/services/whatsapp/health_service.rb:12-14`). So *"Those are the ones this installation has actually seen"* is
unsupported for three of its five referents.

The deeper defect is that the editorial rule is doing harm where it is applied honestly. 131047 is the code Meta
publishes for the single most common WhatsApp refusal (N2), the corpus devotes an entire article to that refusal's
*symptom*, and the product duplicates Meta's sentence in its own locale file (`config/locales/en.yml:185`) — yet
the number has no page and no link, because `whatsappErrorArticle` resolves only mapped keys
(`app/javascript/dashboard/helper/documentationLinks.js:163-168`, mapping five codes at `:44-48`). "Do not invent an
explanation" is a good rule. "Do not document a code Meta documents" is not the same rule, and the sentence at
`:102-105` conflates them.

### 2.11 The window is per-conversation in Lynomia and per user-plus-number at Meta. — **major**, case (c)

**Claim.** *"It runs for **24 hours** and is **per conversation**"*, under the heading *"How the clock actually
runs"*, in an article that opens *"it is not a Lynomia Chat rule. It is WhatsApp's"*
(`the-whatsapp-24-hour-window.md:8-9`, `:25`).

**Why it is wrong.** Lynomia computes the window from the last incoming message **of that conversation record**:
`app/services/conversations/message_window_service.rb:35-37` — `last_incoming_message.created_at + time`, with
`MESSAGING_WINDOW_24_HOURS` selected for `Channel::Whatsapp` at `:27-28`. Meta does not key it to anything of the
sort. N1 says *"When a WhatsApp user messages you or calls you, a 24-hour timer called a customer service window
starts"*, and N2's text for 131047 keys it to the pair: *"since the recipient last replied to **the sender
number**."*

The divergence is reachable, not theoretical. A contact whose earlier conversation was resolved and who then writes
again produces a second conversation; the first conversation's composer stays shut because *its* last inbound
message is old, while Meta's window for that user and that number is open. The article's *"Breaking it is not
possible — the message simply does not go out"* (`:20`) describes Lynomia's local pre-emption, not Meta's refusal —
see §2.4.

### 2.12 Retrying 131049 is not documented to harm your quality rating. — **medium**, case (c)

**Claim.** *"pressing Retry would simply collect the refusal again — and **every attempt is one more signal against
your number's quality rating**"* (`whatsapp-errors/whatsapp-error-131049.md:22-23`).

**Why it is wrong.** N10, Meta's own page for this limit, states the consequence of retrying early: it *"will
likely result in additional error responses and **can reduce the accuracy of campaign delivery reporting**."* Meta
names reporting accuracy, not quality rating. The quality-signal claim is Lynomia's engineering rationale, written
in three places in this codebase — `custom/app/services/whatsapp/delivery_failure.rb:5-7`,
`app/controllers/api/v1/accounts/conversations/messages_controller.rb:29-32`,
`app/javascript/dashboard/components-next/message/MessageError.vue:49-51` — and in a user-facing string at
`config/locales/en.yml:186`. It may be true. No Meta page says it, and the article asserts it as the reason Meta's
mechanism punishes you.

Two more precision defects in the same article. *"A message genuinely about one transaction belongs in UTILITY,
which this cap **does not apply to the same way**"* (`:37-39`) — N10 scopes the limit to marketing template
messages outright: *"Each marketing template message delivered counts towards the per-user marketing limit."* It
does not apply to utility at all, and "not the same way" invites a reader to think a weaker version applies. And
*"Reply inside the conversation instead"* (`:41`) understates what N10 grants: *"Marketing messages sent within
this window do not count towards the limit"* — a marketing template sent inside an open window is exempt, not
merely a different activity.

### 2.13 131049's geography is undocumented, and it changes who can ever see it. — **medium**, case (b)

**Claim (by omission).** `whatsapp-error-131049.md` presents the per-user marketing cap as universal, and its
worked example is a 4,000-contact promotion with 37 failures (`:46-49`).

**Why it is wrong.** N10 states two exclusions plainly: *"Per-user marketing template message limits are not
currently active"* for businesses or users in the **EEA, UK, Japan or South Korea**; and WhatsApp *"does not
currently deliver marketing template messages to WhatsApp users with United States phone numbers"* at all. A
Kuwait-based business sending to a US number does not get 131049 — it gets no marketing delivery. Neither fact
appears anywhere in the corpus, and the article that would need them most, `whatsapp-campaigns.md`, has no
geography section either.

### 2.14 131042's cause list drops Meta's most likely cause and adds one Meta does not state. — **medium**, case (b)

**Claim.** *"most often no payment method, a card that was declined, or **a currency that does not match the
account**"* (`whatsapp-errors/whatsapp-error-131042.md:9-11`).

**Why it is wrong.** N2's own cause list for 131042 is: an unattached payment account, an over-limit or inactive
credit line, a deleted or suspended account, **unset** timezone or currency, and a **pending or declined
MessagingFor request**. Meta's Details string is the broader *"There was an error related to your payment
method."* So the corpus converts *unset* currency into *mismatched* currency — a different and unfixable-sounding
thing — and omits both the credit-line causes and the MessagingFor request, which is the cause that actually
applies when a solution partner shares a line of credit. The article's three-step remedy (`:27-30`) cannot resolve
a pending MessagingFor request, so a reader in that state follows the steps, finds a valid card, and concludes the
article is wrong.

### 2.15 Coexistence: the 24-hour deadline is right, the 180 days behind it is missing. — **medium**, case (b)

**Claim.** *"It does not import your past chats. Nothing from before the connection comes across. **Meta only
allows that synchronisation in the first 24 hours after onboarding**, and Lynomia Chat does not implement it at all
— so it cannot be turned on later for a number that is already connected either."*
(`whatsapp-business-coexistence.md:40-42`).

**Why it is partly wrong.** The 24-hour figure is a **request deadline**, and N9 confirms it: *"you have 24 hours
to synchronize their messaging history"*, after which *"the business must be offboarded and complete the flow
again."* What the sentence loses is the thing a migrating business cares about: the history available is **180
days**, delivered in three phases (day 0–1, day 1–90, day 90–180), with media asset ids only for media from the
14 days after onboarding, individual chats only (*"Group chats will not be synchronized"*), and **contacts
included** (*"All contacts with a WhatsApp number can be synchronized"*). A reader is left believing Meta offers a
day of history when Meta offers six months of it, and that the choice not to implement it costs almost nothing.

The article's own next bullet, *"It does not import your contacts"* (`:43-44`), is correctly scoped as a Lynomia
statement, but sits next to a Meta claim that is wrong, so the reader cannot tell which is which — the same failure
mode as §2.4 and §2.11.

### 2.16 Phone-number status meanings are attributed to Meta without a retrievable source. — **medium**, case (c)

**Claim.** `whatsapp-errors/whatsapp-number-status.md:13-20` tabulates six statuses under the column heading
**"What Meta means by it"**, including *"**Restricted** | the number has hit a limit Meta imposed. Sending is
reduced or stopped | partly — it lifts as quality recovers"* and *"**Rate limited** | too many messages too quickly
for this number's tier"*.

**Why it is wrong as framed.** The six values are **Lynomia's own risk list**:
`app/services/whatsapp/health_service.rb:39` — `RISKY_STATUSES = %w[BANNED RESTRICTED RATE_LIMITED FLAGGED
DISCONNECTED DELETED]`. The article says so honestly in its prose (*"Six values are treated here as worth your
attention"*, `:10`) and then dishonestly in its table header. N11 states only that *"Business phone numbers must
have a status of 'connected' in order to send and receive messages via the API"* and refers the reader to the API
reference for the enumeration; that reference returned navigation only (§1.1), so **I could not retrieve Meta's
definitions for any of the six**. The definitions in the table are therefore unsourced, and two of them make
specific causal promises ("it lifts as quality recovers", "too many messages too quickly") that a reader will act
on. See §4 — this is not "unverifiable", it is "a column header claiming a source that was never read".

### 2.17 Account Health is sold as the place to find out why sending fails, and it does not read the Meta field built for that. — **medium**, case (c)

**Claim.** *"Open **Settings → Inboxes → the inbox → Account Health**. It reports what Meta says about the number,
and **almost every connection problem is visible there**"* (`whatsapp-troubleshooting.md:59-60`), with the
131042 article conceding one hole: *"Account Health does not report billing. The number can look entirely healthy
and still refuse every paid message"* (`whatsapp-error-131042.md:51-52`).

**Why it is wrong.** N12 documents a purpose-built field for precisely this question — `health_status`, with
`can_send_message` of `AVAILABLE` / `LIMITED` / `BLOCKED`, an `entities` array covering every node involved, and
human-readable reasons including *"Message templates can only be sent out if they are approved"* and the
display-name reason quoted in §2.2. N2 recommends it under 131031 as well (*"the Health Status API … may provide
additional insight into the reason or reasons for the account lock"*).

Lynomia does not request it. `app/services/whatsapp/health_service.rb:104-121` lists the requested phone fields —
`quality_rating`, `whatsapp_business_manager_messaging_limit`, `status`, `code_verification_status`,
`account_mode`, `display_phone_number`, `name_status`, `verified_name`, `webhook_configuration`, `throughput`,
`last_onboarded_time`, `is_on_biz_app`, `platform_type` — and `health_status` is not among them. So "almost every
connection problem is visible there" is a claim about a screen that omits Meta's own send-eligibility verdict. The
corpus is reporting the product's coverage as if it were Meta's.

### 2.18 "The three ways to connect" over a four-row table. — **minor**

`whatsapp/connect-whatsapp.md:3` and `:26` promise three routes; the table at `:28-33` lists four (Cloud quick,
Cloud manual, WhatsApp Business, Twilio), and `:106` then refers to *"two provider cards"*. Three cards, four
routes, one number in the heading. Trivial to fix and visible in the article's own description field, which is
indexed.

### 2.19 Template variable placement is presented as Meta's published rules. — **minor**, case (b)

**Claim.** *"Lynomia Chat checks **the structural rules WhatsApp publishes** — lengths, component types, variable
placement, button counts and samples"* (`whatsapp-templates.md:60-61`), having just stated three: *"a variable
cannot be the first or last thing in the text; two variables cannot sit next to each other — put words between
them; numbered variables have to run 1, 2, 3 in the order they appear, and named ones have to be unique lowercase
words"* (`:45-49`).

**Why it is wrong.** The third rule is published: N6 states *"Named parameters must be unique, single strings of
lowercase characters and underscores"* and *"Positional parameters must be ordered array index numbers starting
from 1"*, and N14 adds the ordering requirement for example values. The first two — no variable at the start or end,
no adjacent variables — **appear on none of N5, N6, N8 or N14**, the four pages that carry template structure. They
are widely believed, they are probably good advice, and they may well be enforced in review; but the sentence
claims Meta publishes them and no page I read does. Either source them or stop calling them published rules.

### 2.20 Template numbers Meta publishes and the corpus does not. — **minor** (gap, case (b) by omission)

Every length limit the corpus does state is correct (§3). What is missing, all from N5–N8 and all the kind of
number a template author hits:

| Number | What it governs | Row |
|---|---|---|
| **512 characters** | maximum template name length, lowercase alphanumeric and underscores | N8 |
| **250 / 6,000** | templates per WhatsApp Business Account — unverified portfolio versus verified portfolio with an approved display name | N8 |
| **100 per hour** | maximum templates creatable in one WABA per hour | N8 |
| **up to 24 hours** | *"Review can take up to 24 hours"* | N6 |
| **2,000 characters** | URL button URL length; button labels 25; phone number 20 | N5 |
| **12 months / 28 days** | unused templates archived, then deleted — **observational (O3)**, and relevant to the article's *"No longer at WhatsApp"* state | O3 |

The last row matters for `whatsapp-template-lifecycle.md:32-37`, which presents a missing template as *"Lynomia
Chat's own observation rather than a state WhatsApp reports"*. If O3 is right, Meta has a documented mechanism that
makes templates disappear, and the article's explanation is incomplete rather than wrong.

### 2.21 There is no media type or size table anywhere in the WhatsApp corpus. — **major** (gap)

The brief asked me to attack the media type and size tables. **There are none to attack.** A grep for `MB`, `KB`
and "size limit" across `custom/db/documentation/en/` returns three hits, all about CSV contact import and support
attachments (`contacts/import-contacts.md:31`, `:162`; `troubleshooting/contact-lynomia-support.md:30`). Not one
WhatsApp article states a media size, a supported format, or a media expiry.

That is a gap, not a safety: the product has a WhatsApp attachment path, Meta's limits are published and specific,
and §2.1 shows that the one article in the section that touches media sends the reader to the wrong cause partly
*because* no article gives them the right one. The numbers, verbatim from N3, with no Lynomia-side verification
claimed:

| Type | Limit | Formats as N3 states them |
|---|---|---|
| Audio | **16 MB** | AAC, AMR, MP3, MP4 Audio, OGG — *"OPUS codecs only; base audio/ogg not supported; mono input only"* |
| Document | **100 MB** | txt, xls/xlsx, doc/docx, ppt/pptx, pdf |
| Image | **5 MB** | JPEG, PNG — *"Images must be 8-bit, RGB or RGBA"* |
| Sticker | **100 KB** static, **500 KB** animated | WebP only; *"WebP images can only be sent in sticker messages"* |
| Video | **16 MB** | 3GPP, MP4 — *"Only H.264 video codec and AAC audio codec supported"* |
| Media ID | **30 days** from the API, **7 days** in webhooks | — |
| Media URL | **5 minutes** | *"after which you must query the ID again to get a new URL"* |
| Link-hosted asset | cached **10 minutes** | N1 |

### 2.22 Report 016, checklist item 13, can be closed. — correction to a report, not a refutation of the corpus

`016-24-hour-window.md` records as **unverified** the article's claim that the business messaging limit *"is shared
by every WhatsApp number in the business portfolio"* (`the-whatsapp-24-hour-window.md:73`) and routes it to agent
018. N4 settles it normatively: messaging limits are *"calculated and set at the business portfolio level and are
shared by all business phone numbers within a portfolio."* **The corpus claim is correct** and item 13 should move
from 016's open list to its confirmed list. One caveat worth carrying: N4 also refers in places to *"your business
phone number's messaging limit"*, so Meta's own page is inconsistent about the unit even while stating the sharing
rule — record the inconsistency, do not resolve it.

I also confirmed, against the live pages, 016's items 1, 2, 3, 19 and 21 (calls open and reset the window; the
closed service-message list; the opt-in reminder; reactions are window-gated) and its §4 numbers for 24 hours,
30 days (mark-as-read), 25 seconds (typing indicator) and 10 minutes (link cache). Report 016 is the most reliable
document in this area and its §8 checklist should be treated as the work list for the window article.

---

## 3. Survived

Claims I tried to break and could not. This section is as important as §2, and several entries here were hard to
confirm, so they should not be re-litigated.

**Template structure — every length and count in the corpus is right.** `whatsapp-templates.md:34-37` against N5:
text header *"Maximum 60 characters"* and one parameter ✓; body *"Maximum of 1024 characters"* ✓; footer
*"60 characters maximum"* ✓; buttons *"up to 10 button components in total"*, *"limited to 10 quick reply buttons"*,
*"limited to two URL buttons"*, *"limited to one phone number button"*, *"Templates are limited to one copy code
button"* ✓. Even the grouping rule survives verbatim — N5 requires quick replies to form one contiguous group
(*valid:* Quick Reply, Quick Reply, URL, Phone; *invalid:* Quick Reply, URL, Quick Reply), which is exactly
*"Keep the quick replies next to each other — WhatsApp refuses them scattered among the others"*. And
`:39`, *"A website button may hold one variable, and it has to come at the end of the address"*, matches N5's
*"appended to the end of the URL string."*

**Template lifecycle mechanics.** From N7: *"Approved templates can be edited up to 10 times in a 30-day window, or
1 time in a 24-hour window"* ✓ (`whatsapp-template-lifecycle.md:54`); *"Only templates with an `APPROVED`,
`REJECTED`, or `PAUSED` status can be edited"* ✓ (`:114`); *"You cannot edit the category of an approved template"*
✓ (`:61`, `:116-117`); whole-template replacement ✓ (`:57-58`); *"Templates that are in a disabled status cannot be
deleted"* ✓ (`:76`); and the undelivered-template case ✓ (`:73-74`) — N7: *"the template's status is set to
`PENDING_DELETION` and WhatsApp attempts delivery for 30 days."* Status meanings for paused and disabled match N6
and N14.

**The window's core rule and its arithmetic.** 24 hours ✓; closed window means pre-approved templates only ✓;
nothing you send resets it ✓; a second inbound message at 20:00 moves the deadline to 20:00 next day ✓ — N1's verb
is *"resets to 24 hours"*, which is what the worked example describes. The apparent contradiction report 016 flags
at its item 20 (*"There is no way to reopen it from your side"* versus *"the customer's reply to it opens a fresh
24 hours"*) is **not** a contradiction: both are true and both are N1's position. It reads badly; it is not wrong.

**The messaging limit's unit.** *"How many **unique customers you may start a conversation with** in a rolling 24
hours — not how many messages you may send. Replying inside the 24-hour window does not count against it"*
(`whatsapp-quality-and-limits.md:29-31`) matches N4 closely: *"the maximum number of unique WhatsApp user phone
numbers your business can deliver messages to"* outside a customer service window, *"within a moving 24-hour
period."* The product's own tooltip is equally accurate
(`app/javascript/dashboard/i18n/locale/en/inboxMgmt.json:1014`).

**Per-user cap opacity.** *"Lynomia Chat cannot tell you how close a contact is to the cap. Meta does not report
that, so the first sign is the refusal"* (`whatsapp-error-131049.md:58-59`) ✓ — N10 publishes no number and says
*"WhatsApp determines this based on several factors"* and *"adapts automatically over time based on a person's
recent engagement levels."* The 24-hour wait advice ✓ matches N2 and N10.

**Coexistence facts.** *"The WhatsApp Business app, version 2.24.17 or later"* (`whatsapp-business-coexistence.md:54`)
✓ exactly N9. The 24-hour sync request deadline ✓ N9 (see §2.15 for what it omits). The echo mechanism —
*"a reply sent from the phone appears in the Lynomia Chat conversation as an outgoing message … Each echo is matched
by its WhatsApp message id"* (`:31`, `:36`) ✓ N9's `smb_message_echoes` webhook, which the page says you *"must
process … and display them in the contact's message thread."* *"It is an official Meta connection; nothing is
scanned, scraped or proxied"* ✓. And the pre-release caveat at `:16-19` is exemplary: it says the route is
unreleased, says what has and has not been tested, and tells the reader not to plan a migration around it.

**Lynomia-side claims I checked in code and could not break.** *"A failure older than a day cannot be retried from
the conversation"* (`whatsapp-find-a-failed-message.md:72`) ✓ —
`app/javascript/dashboard/components-next/message/MessageError.vue:64`, `!hasOneDayPassed(createdAt.value)`.
*"Retry is withdrawn where a retry would simply repeat the refusal"* ✓ —
`MessageError.vue:56-61` and `messages_controller.rb:35-41`, keyed on `recipientScoped`. *"Templates refresh from
WhatsApp automatically every few hours"* (`whatsapp-templates.md:124`) ✓ — three hours, `app/jobs/channels/whatsapp/
templates_sync_scheduler_job.rb:8`; health is six, `health_sync_scheduler_job.rb:8`, so "every few hours" is right
for both. *"A WhatsApp number running through Twilio has the same 24 hours"*
(`the-whatsapp-24-hour-window.md:75-76`) ✓ in code — `message_window_service.rb:46-48` — though it is Lynomia's
constant and no Meta page I read mentions any BSP, so it survives as a product claim, not a Meta one. *"Facebook,
Instagram and TikTok differ"* ✓ — `:50-60`, with TikTok at 48 hours.

**Two statements that are models of the register the rest of the section should use.** `whatsapp-error-131060.md`
is honest that the content is unrecoverable and that nothing of the business's failed — and it refuses to speculate
about what was sent. `whatsapp-number-already-connected.md` explains installation-wide uniqueness, says plainly
that only the operator can see where the number is, and says why that is deliberate. Neither attributes a Lynomia
decision to Meta.

---

## 4. Not checkable

**Meta's enumeration of phone-number `status` values.** N11 refers the reader to the WhatsApp Business Phone Number
API reference; that URL returned navigation and footer only, and a site-restricted search produced no definition
list for `FLAGGED`, `RESTRICTED` or `RATE_LIMITED`. So §2.16's six definitions are unsourced rather than
contradicted. What is needed: a successful read of the Graph API reference for the phone number node, or a Meta
Business Help page that enumerates them.

**Meta's display-name guidelines.** `facebook.com/business/help/338047025165344` served only its title. The four
refusal reasons at `whatsapp-display-name.md:24-27` are therefore unverified here. Report 054's G7 says report 014
enumerates a different list (employee or individual name, unrelated business name, unacceptable format, not
consistent with branding) and adds a step the article omits — that an approved new name *"does not take effect until
the number is re-registered"*, within a 14-day window (`014-waba-phone-registration.md:161-164`, `:318-326`). I
could not reach a primary page for either, so I record 014's list as the better-sourced one without adopting it.

**Whether a messaging limit can fall, and on what trigger.** N4 documents only increases. O2 asserts a one-level
decrease after 7 days Flagged and is a search summary, not a page. Reports 018 and 089 agree the page is silent.
The corpus must not state a downgrade rule until a page does; equally, nobody should write "limits never fall",
which the silence does not license.

**Whether the quality rating counts non-reply.** The defining help page (O1) served no body. The signals named in
its search summary are feedback signals, and the template-pausing documentation names low read rates
(N6, N14) — but a page stating the rating's full input list was not read.

**Whether read receipts and typing indicators are charged, and whether they are truly ungated by the window.**
Report 016 records this as an ambiguity and is right to. I did not reduce it. Meta's silence is silence.

**Whether Meta returns 131049, 131042 or 131053 synchronously as well as on the webhook.** This decides whether
Lynomia stores them with a numeric code at all —
`app/services/whatsapp/providers/whatsapp_cloud_service.rb` reads only `error.message` at request time, while the
status-webhook path writes `"<code>: <title>"` (`docs/real-whatsapp-uat/05-outbound-new-contact.md:130-144`,
`06-delivery-status.md:75-85`). 054 lists the same open question (`054:345`). Settling it needs a real send, which
no agent in this program may perform.

**Everything about this installation's real traffic.** `docs/real-whatsapp-uat/10-real-uat-results.md:3` establishes
that no real WABA call, inbound message or outbound send has been performed. Any claim in any document that a code
was "observed in production" must be read against that file until an operator runs
`bundle exec rails whatsapp:diagnose` on the real server and the output is recorded. Until then, "observed" in this
program means "present in a fixture, a spec or an example payload" — and §2.10 shows that distinction has already
been lost once in a report.
