---
agent: 018
scope: WhatsApp messaging limits and tiers, quality rating, and throughput — what raises and lowers each, number and account restriction, and appeals
confidence: medium
sources_normative: 9
sources_observational: 2
---

Confidence is **medium**, not high, for one reason stated up front: the three things in scope divide cleanly
between documentation I could read and documentation I could not. **Messaging limits** and **throughput** are
documented on live developer pages that render, and everything claimed about them below is quoted from a page I
actually read. **Quality rating** is documented primarily on a Meta Business Help article
(`896873687365001`) whose body is JavaScript-gated and did not render through fetch — I confirmed its title and
nothing else. The green/yellow/red labels, the `Flagged` and `Restricted` number states, and the "7 days flagged
→ limit drops one level" mechanic that the whole support industry repeats are therefore recorded below as
**not confirmed from a readable normative page**. That matters, because those are precisely the claims the
Lynomia article makes.

## 1. Source register

| # | Source URL | Page title | Product | API/version context | Date checked | Normative/observational |
|---|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/whatsapp/messaging-limits` | Messaging Limits | WhatsApp Cloud API | Phone Number API; field `whatsapp_business_manager_messaging_limit`; `messaging_limit_tier` marked deprecated | 2026-10-13 | normative |
| S2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/throughput` | Throughput | WhatsApp Cloud API | per registered business phone number; `GET /<PHONE_NUMBER_ID>?fields=throughput` | 2026-10-13 | normative |
| S3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers` | Business phone numbers | WhatsApp Cloud API | Phone Number API; fields `status`, `quality_rating`, `code_verification_status`, `name_status` (beta), `throughput` | 2026-10-13 | normative |
| S4 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/policy-enforcement` | WhatsApp Business Platform policy and spam enforcement | WhatsApp Business Platform | WABA-level; Business Support Home appeal flow | 2026-10-13 | normative |
| S5 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | Error Codes (Cloud API support) | WhatsApp Cloud API | Cloud API error surface | 2026-10-13 | normative |
| S6 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/send-messages` | Service messages / Send messages | WhatsApp Cloud API | quality-rating signal list and visibility | 2026-10-13 | normative |
| S7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/support/health-status/` | Messaging and Calling Health Status | WhatsApp Cloud API | `health_status` field on WABA, phone number, template | 2026-10-13 | normative |
| S8 | `https://developers.facebook.com/docs/whatsapp/api/rate-limits/` | Messaging Limits | WhatsApp Business Platform | legacy URL; **serves the S1 content** | 2026-10-13 | normative |
| S9 | `https://www.facebook.com/business/help/896873687365001` | About Your WhatsApp Business Phone Number's Quality Rating \| Meta Business Help Center | Meta Business Help | not readable | 2026-10-13 | normative source, **body not retrievable** |
| S10 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/quality-rating` | (title not stated; path confirmed via login-redirect) | WhatsApp Cloud API | not readable | 2026-10-13 | normative source, **body not retrievable** |
| O1 | WebSearch result summaries citing S9/S8 for `Flagged`/`Restricted` day-counts | — | — | — | 2026-10-13 | **observational, unconfirmed** |
| O2 | Third-party BSP help centres (Exotel, webexconnect, SMS-Magic, AWS Social Messaging, 360dialog) | various | — | — | 2026-10-13 | **observational, unconfirmed** |

## 2. The rules

### The three things are three different things

This is the heart of the brief, so it goes first, in one table. Businesses confuse these constantly because all
three produce a failed send and all three sound like "we are being rate limited."

| | Messaging limit (tier) | Quality rating | Throughput |
|---|---|---|---|
| **Measures** | how many **unique recipients** you may start a conversation with | how **recipients react** to your messages | how many **messages per second** the API accepts |
| **Unit** | unique WhatsApp user phone numbers, outside a customer service window (S1) | GREEN / YELLOW / (RED — see §6) | messages per second, **inclusive of inbound and outbound and all message types** (S2) |
| **Window** | a **moving 24-hour period** (S1) | the **past seven days**, weighted toward recent activity (S6) | per second |
| **Scope** | S1 states it at both **portfolio** and **business phone number** level and does not reconcile the two (see §6) | per **business phone number** (S3, `quality_rating`) | per **registered business phone number** (S2) |
| **Error when exceeded** | **not stated on S1**; in practice `131048` (S5) | none — it is a score, not a gate | `130429` (S2, S5) |
| **Fixed by** | business verification, or proven volume at quality | sending messages people want | backoff, and throughput upgrade eligibility |

The practical consequence: a business that hits its **messaging limit** has a *permissions and reputation*
problem that more servers cannot solve, while a business that hits **throughput** has a *sending-infrastructure*
problem that better opt-in lists cannot solve. They are fixed by different people.

### (1) The messaging limit / tier system

S1 gives the ladder as five levels: **250** (the default for new portfolios), **2,000**, **10,000**, **100,000**,
and **Unlimited** — the last listed as "Unlimited (via automatic scaling)."

What counts against it is narrow and widely misunderstood: the limit is the maximum number of **unique WhatsApp
user phone numbers you can message outside a customer service window**, within a moving 24-hour period. It is
not a message count. Two consequences follow directly from the wording and both are worth stating in help
content: sending five messages to one recipient consumes one unit of the limit, not five; and **replies inside a
customer service window do not consume it at all**, because the limit is explicitly scoped to messages sent
outside one. S1 does not break the limit down by conversation category or message type.

Getting off 250 is a **gated step, not a growth curve**, and this is the single most actionable fact in the whole
area. S1 states three alternative "scaling paths" to reach 2,000, any one of which suffices:

- verify your business; or
- have your partner verify your business, if a partner onboarded you; or
- "Send 2,000 delivered messages outside of customer service windows" to unique WhatsApp user numbers within a
  **30-day moving period**, using templates with a high quality rating.

After a path is completed Meta "analyzes your message quality" and approves or denies. On approval S1 says Meta
"immediately increases your business phone number's messaging limit to 2,000." On denial it "maintains your
business phone number's messaging limit at its current level" — a denial does not demote.

Above 2,000 the ladder becomes automatic, and requires **both** conditions:

- high-quality messages across all your business phone numbers and templates; and
- "In the last 7 days, your business has utilized at least half of your current messaging limit."

When both hold, "your portfolio's limit increases by one level within 6 hours." The utilisation condition is the
one businesses never anticipate: a business sending 3,000 conversations a day will never reach 10,000, because it
is not using half of 10,000 — the ladder requires demonstrated demand, not merely good behaviour.

Reading the current value: S1 gives the field as `whatsapp_business_manager_messaging_limit` on the Phone Number
API, with `TIER_250` as the only example value shown, and marks the older `messaging_limit_tier` field
**deprecated**. S3 adds that reaching a messaging limit of 2,000 is one trigger for raising the registered
number cap from 2 to 20.

**Downgrade is not stated on S1.** I read the page twice, including past the scaling section, looking
specifically for "decrease", "downgrade" or "lower". The page describes only increases and the no-op on denial.
See §6 — this is the most consequential gap in the area and it is where the Lynomia article is exposed.

### (2) Quality rating

S6 is the only page I could read that describes the mechanism, and it is clear on the two things that matter
most. The rating is "determined by a combination of user feedback signals like blocks, reports, mutes, archives"
together with the reasons users give when blocking. It is based on how messages were received "over the past
seven days," weighted by recency. Note what is in that list: **mutes and archives count**, which means a
recipient who neither blocks nor reports but silently buries the thread still damages the rating.

Where it is visible: S6 states the rating is "displayed in the WhatsApp Manager > Account tools > Phone numbers
panel," alongside number status and messaging limits — the three appear side by side in Meta's own UI, which is
itself part of why businesses conflate them. S3 gives the API field as `quality_rating` on the business phone
number.

S6 also records a volatility warning worth passing to operators: high-traffic numbers may see "quality changes
within short intervals (even within minutes)." A single yellow reading is not necessarily a trend.

How it interacts with the messaging limit: **S6 lists them together but does not explain the interaction.** What
I *can* confirm normatively is the interaction in the other direction and in a third place:

- quality gates **upgrades**: S1 requires high-quality messages for automatic scaling, and high-quality-rated
  templates for the volume scaling path;
- quality gates **throughput**: S2 requires a `quality_score` of `YELLOW` ("Medium quality rating") **or higher**
  for the 1,000 mps upgrade — which incidentally attests `YELLOW` as a real API value and confirms that YELLOW is
  not disqualifying for throughput.

Recovery: no page I could read states a recovery procedure or period. Since the rating is a seven-day
recency-weighted window of recipient feedback (S6), it recovers as that window rolls forward, but I am not
willing to state a day count that no readable page gives.

### (3) Throughput

S2 is the cleanest page in the area. Default throughput is **80 messages per second (mps)** per registered
business phone number. Higher throughput is **up to 1,000 mps**. Coexistence numbers — numbers in use with both
the WhatsApp Business app and Cloud API — have a **fixed 20 mps** and do not scale.

Throughput is "inclusive of inbound and outbound messages and all message types." This is a real trap: a busy
inbox consumes the same budget as a campaign, so a business running a large broadcast while handling heavy
inbound traffic can hit 130429 at an outbound rate well below its nominal ceiling.

The upgrade is **automatic and free** — S2 says eligible numbers are upgraded without any request and that higher
throughput "does not incur additional charges or affect pricing." Eligibility requires all three of: the
business portfolio has an **Unlimited** messaging limit; the number messages **100K or more** unique WhatsApp user
numbers outside a customer service window within a moving 24-hour period; and the number has a `quality_score` of
`YELLOW` or higher. The upgrade itself "can take up to 1 minute, during which the number will not be usable" and
the API returns `131057` (maintenance mode) for that minute.

Exceeding throughput returns `130429`, which S2 says is returned "until you are within your allowed level
again." S5 gives the retry guidance as "Try again later or reduce the frequency with which the app sends
messages." **Neither page states a retry interval, a backoff curve, or a `Retry-After` header** — Meta's guidance
here is qualitative only, and any specific backoff figure a business is told is somebody's invention.

S2 closes by stating that business phone numbers, "regardless of throughput," remain subject to their WhatsApp
Business Account rate limit and template messaging limits — i.e. clearing throughput does not clear the others.

### Number and business account restriction

Two separate enforcement systems exist and the documentation splits them cleanly.

**Policy and spam enforcement (S4)** applies at the **WhatsApp Business Account** level, not the phone number
level, and is a five-rung ladder of increasing duration. S4 explicitly says it "does not include information on
messaging limits based on quality rating" — so this ladder and the tier system are genuinely independent
mechanisms, and a business can be in good standing on one and blocked on the other.

| Rung | What it blocks | Trigger | Duration |
|---|---|---|---|
| Warning | nothing; informational, names the violated policy | initial violation | not stated |
| Marketing / utility / authentication block | sending those template categories, **and adding phone numbers** | repeated violations: spam, template misclassification, high-risk categories | **1 or 3 days** |
| Full messaging block | sending any messages, **and adding phone numbers** | continued violations | **5, 7, or 30 days** |
| Account lock | sending any messages | continued violations | **indefinite — removable only by appeal** |
| Permanent disablement | removal from the platform | no change after multiple warnings and blocks | **permanent** |

S4 adds that accounts with evidence of severe harm (child exploitation, scams, terrorism, illegal drug sales) may
be **offboarded immediately** without the ladder, and that excessive negative user feedback may also lead to
limits or offboarding.

**Phone-number-level states** are where my evidence thins out. S3 gives the API field as `status`, shows
`CONNECTED` in its example, states that a number "must have a connected status to send and receive messages via
the API", and then **defers the full enum to the WhatsApp Business Phone Number API reference** — a page I could
not reach (the Graph API reference URL I tried returned 404 and search did not surface it). So the authoritative
list of number states is, for this report, **not obtained**. S3 does define the adjacent `name_status` enum
(`APPROVED`, `AVAILABLE_WITHOUT_REVIEW`, `DECLINED`, `EXPIRED`, `PENDING_REVIEW`, `NONE`) and notes that a number
**banned** on WhatsApp "must be unbanned via the appeal process first" before it can be registered.

A third, different vocabulary exists in **S7**, the health-status API, and it should not be confused with the
`status` enum. `health_status` returns, per entity (`PHONE_NUMBER`, `MESSAGE_TEMPLATE`, `WABA`, `BUSINESS`,
`APP`), one of: **AVAILABLE** ("meets all messaging or calling requirements"), **LIMITED** ("meets messaging or
calling requirements, but has some limitations", with `additional_info`), or **BLOCKED** ("does not meet one or
more messaging or calling requirements", with `errors`). This is the programmatic pre-send check and it is the
right diagnostic surface for a product like Lynomia to read, because it answers "can this number send right now"
across all five entities at once rather than requiring the operator to assemble tier, quality and policy state
by hand.

### Appeals

S4 gives an exact procedure, which is the most directly actionable content in the whole area:

1. In **Business Support Home**, select the relevant WABA.
2. Choose the violation and click **Request Review**.
3. In the Business Manager dialog, enter supporting details and click **Submit**.
4. The request moves to the **In Review** tab.
5. The decision arrives via Business Manager, **typically within 24 to 48 hours**.
6. The outcome is either **Unchanged** or **Reversed**.

Two caveats S4 states plainly: restricted or disabled accounts **can still appeal**; and **not all spam
violations can be appealed** — in those cases the business must simply wait for the restriction to end. S3 adds
the separate appeal path for an unbanning a banned number. S7 shows an appeal route for template decisions
("Edit or appeal the message template review decision", error 141002).

There is **no appeal for a messaging limit tier or a quality rating**. Neither is an enforcement decision, so
neither is reviewable; the only levers are business verification and recipient behaviour respectively. That
distinction is worth stating in help content, because operators routinely try to appeal a tier.

## 3. Error codes and failures

All rows from S5 unless noted. Titles are left `not stated` where S5 presents a description without a titled
label, per the no-invention rule.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 130429 | not stated | "(#130429) Rate limit hit" (given as the example `message` value, not in the error table) | "Cloud API message throughput has been reached." | "Try again later or reduce the frequency with which the app sends messages." No interval stated. | nothing; message not sent | S2, S5 |
| 131048 | not stated | not stated | "Message failed to send because there are restrictions on how many messages can be sent from this phone number." S5 adds this may happen when "too many previous messages were blocked or flagged as spam." | Check quality status in WhatsApp Manager; review template limits and template quality docs. No retry guidance stated. | nothing | S5 |
| 131049 | not stated | not stated | "This message was not delivered to maintain healthy ecosystem engagement." | "wait at least 24 hours before resending the template message" — resending sooner only produces another error. See per-user marketing template limits. | nothing | S5 |
| 131056 | not stated | not stated | "Too many messages sent from the sender phone number to the same recipient phone number in a short period of time." | Wait and retry for that recipient; other recipients are unaffected. | nothing | S5 |
| 131064 | not stated | not stated | "Message failed to send because this account has reached its messaging limit due to template classification violations." Applies to template **and** direct sends. | Review and correct template classifications. "The restriction lifts automatically after the enforcement period." | nothing | S5 |
| 131057 | not stated | not stated | "Business Account is in maintenance mode" | Wait. S5 names a throughput upgrade as one possible reason; S2 bounds that at up to 1 minute. | nothing | S2, S5 |
| 80007 | not stated | not stated | "The WhatsApp Business Account has reached its rate limit." | Retry later or reduce request frequency/volume; see WABA Rate Limits doc. | nothing | S5 |
| 4 | not stated | not stated | "The app has reached its API call rate limit." | Check Application Rate Limit in App Dashboard; retry later or reduce call frequency/volume. | nothing | S5 |
| 132015 | not stated | not stated | "Template is paused due to low quality so it cannot be sent in a template message." | Edit the template to improve quality, retry once approved. | nothing | S5 |
| 132016 | not stated | not stated | "Template has been paused too many times due to low quality and is now permanently disabled." | Create a new template with different content. | nothing | S5 |
| 132069 | not stated | not stated | "Flow is in throttled state and 10 messages using this flow were already sent in the last hour." | "Correct the Flow" | nothing | S5 |
| 133016 | not stated | not stated | "Registration or Deregistration failed because there were too many attempts for this phone number in a short period of time" | Number is blocked from further attempts; retry once unblocked. See Registration "Limitations". | n/a (registration, not send) | S5 |
| 141002 | not stated | not stated | "Message templates can only be sent out if they are approved." | "Edit or appeal the message template review decision." | nothing | S7 |

The disambiguation that matters operationally: **130429 is throughput** (too fast), **131048 is a
number-level sending restriction** (reputation/spam), **131064 is a messaging limit reached via template
classification violations** (policy), **80007 is a WABA API rate limit** (too many API calls), and **4 is an app
call-rate limit** (too many API calls, app-wide). Four different fixes, owned by three different people. Note
also that `131048` — not a dedicated "messaging limit exceeded" code — is the code that surfaces number-level
send restriction; **no page I read states which error a send over the messaging-limit tier returns**, so the
mapping from "tier exhausted" to a specific code is an inference I am flagging rather than asserting.

## 4. Limits and numbers

Every number below is quoted from the source row named. Nothing in this table is inferred.

| Value | What it is | Source |
|---|---|---|
| 250 | default messaging limit for new business portfolios; API value `TIER_250` | S1 |
| 2,000 | second messaging limit level, reached via a scaling path | S1 |
| 10,000 | third messaging limit level, via automatic scaling | S1 |
| 100,000 | fourth messaging limit level, via automatic scaling | S1 |
| Unlimited | fifth level, "via automatic scaling" | S1 |
| moving 24-hour period | window the messaging limit is measured over | S1 |
| 2,000 delivered messages / 30-day moving period | volume scaling path to the 2,000 level, to unique numbers outside customer service windows, high-quality templates | S1 |
| half of current limit / last 7 days | utilisation condition for automatic scaling above 2,000 | S1 |
| within 6 hours | time for an automatic scaling increase to take effect | S1 |
| 80 mps | default throughput per registered business phone number | S2 |
| 1,000 mps | higher throughput ceiling | S2 |
| 20 mps | fixed throughput for coexistence numbers (WhatsApp Business app + Cloud API) | S2 |
| 100,000 unique numbers / moving 24-hour period | throughput-upgrade eligibility volume condition | S2 |
| up to 1 minute | throughput upgrade window during which the number is unusable (returns 131057) | S2 |
| past 7 days | quality rating window, weighted toward recent activity | S6 |
| 2 → 20 | registered number cap increase triggered by reaching a 2,000 messaging limit | S3 |
| 1 or 3 days | marketing/utility/authentication block duration | S4 |
| 5, 7, or 30 days | full messaging block duration | S4 |
| 24 to 48 hours | typical appeal decision time | S4 |
| 10 messages / last hour | Flow throttle threshold behind 132069 | S5 |
| at least 24 hours | wait before resending a template after 131049 | S5 |

**Deliberately absent**: any downgrade threshold, any number of days a number stays Flagged, any quality-rating
percentage or score, and any throughput retry interval. No page I read states these. Any figure for them in
Lynomia content must be treated as unsourced.

## 5. Version and deprecation notes

- `messaging_limit_tier` on the Phone Number API is **deprecated**; the current field is
  `whatsapp_business_manager_messaging_limit` (S1). Any Lynomia code or article referencing the old field is
  stale. This should be checked against the repository by the product agents (039/040).
- Meta has **moved these pages from `/docs/whatsapp/...` to `/documentation/business-messaging/whatsapp/...`**.
  The legacy `https://developers.facebook.com/docs/whatsapp/api/rate-limits/` URL (S8) now serves the current
  Messaging Limits content, and `https://developers.facebook.com/docs/whatsapp/overview/phone-numbers` returns
  **404**. Any hard-coded Meta documentation link in Lynomia content is a link-rot candidate; agent 091 should
  sweep for these.
- Both pages I could not read (S9, S10) are the quality-rating pages. The `/documentation/.../quality-rating`
  path (S10) is confirmed to exist — it appeared as a login-redirect target — but served only navigation
  chrome to a plain fetch. Any future agent re-checking quality-rating specifics needs a JS-capable fetch,
  not WebFetch.
- `name_status` is marked **beta** on S3 (S3).

## 6. Ambiguities and gaps

These are recorded, not resolved.

1. **Portfolio or phone number? S1 uses both and never reconciles them.** For the limit itself it says "Meta
   immediately increases your **business phone number's** messaging limit to 2,000"; for automatic scaling it
   says "your **portfolio's** limit increases by one level within 6 hours"; and the automatic-scaling condition
   is phrased as "your **business** has utilized at least half of your current messaging limit" with quality
   assessed "across **all** your business phone numbers and templates." The most coherent reading is that the
   limit is a **portfolio-level** allowance that each phone number inherits, which would mean one bad number
   can hold back every number in the portfolio — but **S1 does not say that**, and I am not going to assert it.
   This is the single most important ambiguity in the area for a multi-number customer and it needs arbitration
   before any Lynomia article states a scope.
2. **Downgrade is undocumented on the page that documents the ladder.** S1 states no decrease mechanism at all.
   The widely-repeated rule — "if the quality rating has been Flagged for 7 days the messaging limit is
   decreased by one level immediately" — was returned to me only inside **search-engine summaries** (O1)
   attributing it to S8/S9, and did **not** appear when I fetched S8 directly, which served the current S1
   content with no Flagged or downgrade text. The claim may be true and may live on S9, which I could not read;
   it may also be stale content the search index still holds. **Status: observational, unconfirmed.** A Lynomia
   article must not state it as Meta's rule until S9 is read with a JS-capable fetch.
3. **Green / yellow / red labels are not confirmed from a readable normative page.** `GREEN` (S3), `NA` (S3),
   `UNKNOWN` (S3) and `YELLOW` (S2, as `quality_score`, glossed "Medium quality rating") are each attested on a
   page I read. **`RED` is not.** It is near-certain to exist, and every third-party source (O2) lists it as
   "Low quality", but no page I read names it. Likewise the human-readable labels High/Medium/Low are attested
   only for YELLOW→Medium (S2).
4. **The number `status` enum was not obtained.** S3 defers it to an API reference page I could not reach. So
   `CONNECTED` is the only number status value I can cite, and `FLAGGED` / `RESTRICTED` / `RATE_LIMITED` are
   **not confirmed as `status` values at all**. O1/O2 describe `Flagged` as a *quality rating* state rather than
   a status, which, if right, means the product vocabulary and the API vocabulary differ — another thing to
   resolve before writing.
5. **No error is documented for exceeding the messaging-limit tier.** S1 defines the limit and is silent on the
   consequence. `131048` is the closest documented behaviour but is worded as a phone-number sending restriction
   tied to blocks and spam flags, not as tier exhaustion. The mapping is unproven.
6. **Quality → messaging limit interaction is explicitly not explained.** S6 displays the two together and does
   not connect them. S4 goes further and disclaims the subject outright: it "does not include information on
   messaging limits based on quality rating." So the central question businesses ask — "will a yellow rating cut
   my limit?" — has **no answer on any page I could read**.
7. **No quality recovery procedure or period is documented** on any page I read.
8. **No throughput retry interval, backoff curve or `Retry-After` header is documented** (S2, S5). Guidance is
   qualitative only.
9. **Conversation categories are absent from the limit definition.** S1 does not say whether marketing, utility,
   authentication and service conversations count differently toward the tier. Overlaps with agents 008 and 017;
   017 owns the separate per-user marketing cap behind 131049 and should not be duplicated here.

## 7. What Lynomia users would ask

### Check against the existing article

`custom/db/documentation/en/whatsapp-errors/whatsapp-quality-and-limits.md` (76 lines, 622 words) is a
well-written article — task-oriented, honest about what the product cannot do, and notably disciplined in
**stating no numbers it cannot source**. It is right about more than it is wrong about. But it makes four claims
I could not confirm and omits one of the three things in scope entirely.

| Article claim | Verdict | Evidence |
|---|---|---|
| "How many **unique customers you may start a conversation with** in a rolling 24 hours — not how many messages you may send" | **confirmed** | S1: unique WhatsApp user phone numbers, moving 24-hour period |
| "Replying inside the 24-hour window does not count against it" | **confirmed** | S1 scopes the limit to messages sent **outside** a customer service window |
| Quality is "a rolling judgement based on how recipients react" | **confirmed** | S6: blocks, reports, mutes, archives, past 7 days, recency-weighted |
| "Tiers go up on their own when you send consistently at quality" | **incomplete and misleading** | S1: the step off 250 is **gated** by a scaling path (business verification, partner verification, or 2,000 delivered messages in 30 days). It does not happen "on its own". Above 2,000 it also requires **using half your current limit in the last 7 days** — a business sending steadily at low volume will never advance, which the article's phrasing promises it will. |
| "...and down when the rating is red" | **not confirmed** | **Downgrade is not stated on S1** (§6.2). Plausible, universally repeated, and unsourced from any page I could read. |
| "Hitting the ceiling shows up as *Rate limited* on the number's status" | **not confirmed against Meta** | No page I read lists a `Rate limited` number status. S3 shows `CONNECTED` and defers the enum; S7 uses `AVAILABLE`/`LIMITED`/`BLOCKED`. This may be a correct description of **Lynomia's own UI string**, which is fine, but it is not Meta's vocabulary and should not read as if it were. |
| Quality signals include "simply never replying" | **not confirmed** | S6's list is blocks, reports, mutes, archives, and block reasons. **Non-reply is not in it.** Mutes and archives are — which is the more useful and more accurate thing to tell a user. |
| "The rating is per number" | **confirmed** | S3: `quality_rating` is a business phone number field |
| "A tier increase is not something you can request in the product" | **true but incomplete** | Correct about the product. But S1 gives the business a **direct lever Meta does document — verify your business** — and the article's "What actually improves both" section never mentions it. This is the article's most costly omission: the fastest route off 250 is a verification task, not a messaging-behaviour change. |
| "What does not help: resubmitting templates, reconnecting the number, changing the display name" | **consistent** | Nothing I read contradicts this; S7's display-name example shows display-name approval raising a message limit, so "changing the display name" is worth narrowing to "changing an already-approved display name". |
| **Throughput** | **absent entirely** | The article covers two of the three things in scope. `130429` and the 80 / 1,000 / 20 mps values (S2) appear nowhere, and nor does the inbound-counts-too trap. |
| **Policy enforcement ladder and the appeal process** | **absent entirely** | S4's five rungs, their durations, and the exact Business Support Home appeal procedure with its 24–48 hour decision time are the most actionable content in the area and are not in the article. The article's "Neither number can be changed from here, or by support. Both are Meta's" is true of tier and quality but risks telling a *blocked* business there is nothing to do, when S4 says there is. |

The Arabic file is 72 lines but only **135 words** against the English 622 — a ratio that suggests it is not a
full translation. Flagged for agent 061; not assessed here.

### What an operator actually needs to act on, and in what order

Of the three, an operator can act meaningfully on **two and a half**. Quality rating is acted on indirectly, by
changing sending behaviour. Messaging limit is acted on directly, by verifying the business. Throughput is acted
on directly, by fixing send pacing. Nothing is acted on by appealing — except enforcement, where appealing is the
*only* action.

The diagnostic order below is deliberately not the order the article presents, because the article leads with
quality rating (slowest to move, acted on indirectly) and never reaches enforcement (fastest to resolve, and
absolutely blocking).

1. **Is the account under policy enforcement?** Check for a warning or block in Business Support Home, and for
   `131064`. If blocked, **nothing else on this list matters** — no amount of good sending behaviour sends a
   message during a full messaging block. Either appeal (S4) or wait out the stated duration. Ask first because
   it is binary, blocking, and has a documented remedy.
2. **Can the number send at all right now?** `health_status` (S7) answers this in one call across phone number,
   template, WABA, business and app, returning `AVAILABLE` / `LIMITED` / `BLOCKED` with reasons. This is the
   check Lynomia's Account Health should be making, and it short-circuits steps 3–6.
3. **Is the template the problem, not the number?** `132015` (paused, low quality), `132016` (permanently
   disabled), `141002` (not approved). Template-scoped and template-fixed; owned by agents 010 and 011.
4. **Is throughput being exceeded?** `130429`. Distinguished from everything else by being *bursty* — it appears
   under load and vanishes when sending slows. Remember inbound counts (S2), so check it during busy inbound
   periods too. Fix is pacing, not reputation.
5. **Is the messaging limit the ceiling?** Read `whatsapp_business_manager_messaging_limit`. If it is `TIER_250`,
   the answer is almost always **verify the business** (S1) — the one high-leverage, documented, immediately
   actionable step in the whole area. If it is higher and the business wants more, check the utilisation
   condition: are they using half their current limit over 7 days (S1)? If not, the ladder will not move and no
   behaviour change will move it.
6. **Is quality yellow or red?** Slowest to diagnose and slowest to fix, because it is a seven-day
   recency-weighted window of recipient feedback (S6). Act on it, but do not expect same-day movement, and do
   not read a single reading as a trend on a high-traffic number (S6).
7. **Is it the per-user marketing cap?** `131049`, wait at least 24 hours before resending (S5). Owned by agent
   017 — this is a per-recipient cap, not a tier, and the article is right to link it but should not imply it is
   a tier symptom.

### Questions this area will produce for the support desk

- "Why is my limit still 250 when I have been sending for months?" — the verification gate (S1); the commonest
  and most fixable ticket in the area.
- "We are nowhere near our limit but sends are failing." — throughput (`130429`), or a template problem, or
  enforcement. Three different answers; the article currently supports none of them.
- "Does answering customers use up my limit?" — no (S1), and this answer prevents real operational damage,
  because businesses throttle their own support replies to protect a limit those replies never touched.
- "Our rating went yellow this morning and green by lunch." — expected on a high-traffic number (S6).
- "Can we appeal our tier / our quality rating?" — no; neither is an enforcement decision. Appeals exist for
  policy violations, template decisions and number bans (S4, S3, S7).
- "Will a second number double our capacity?" — unanswerable until ambiguity §6.1 is resolved. If the limit is
  portfolio-level, the answer is **no**, and the article's existing hedge on this point is well judged.
- "How long until our limit comes back after being cut?" — **no documented answer** (§6.2, §6.7).
