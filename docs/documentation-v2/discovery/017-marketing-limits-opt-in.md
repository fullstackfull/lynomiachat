---
agent: 017
scope: Marketing message limits, per-user caps, opt-in rules, quality-based throttling — the Meta rules that govern what Lynomia's campaign feature does
confidence: high
sources_normative: 13
sources_observational: 2
---

## 1. Source register

Every claim below references a row by its ID. Date checked for all rows: **2026-10-13**.

| ID | Source URL | Page title | Product | API / version context | Normative? |
|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/getting-opt-in` | Get opt-in for WhatsApp | WhatsApp Business Platform | No API version stated. Page references the **November 2024** Business Messaging Policy update | normative |
| S2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/per-user-limits/` | Per-user marketing template message limits | WhatsApp Business Platform | No version, no publication date stated | normative |
| S3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/support` | WhatsApp support | WhatsApp Cloud API + Marketing Messages API | States MM API "uses the same error codes as Cloud API" | normative |
| S4 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/support/error-codes` | WhatsApp error codes | WhatsApp Cloud API / MM API | Page marks `error_subcode` **deprecated**; HTTP statuses given only for the MM API table | normative |
| S5 | `https://whatsappbusiness.com/policy/` | WhatsApp Business Messaging Policy (consolidated; includes Commerce Policy) | WhatsApp Business (policy) | **Last updated 23 September 2026.** `business.whatsapp.com/policy` **and** `www.whatsapp.com/legal/commerce-policy` both 301-redirect here | normative |
| S6 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/policy-enforcement` | WhatsApp Business Platform policy and spam enforcement | WhatsApp Business Platform | No dates stated. Explicitly says it does **not** cover quality-rating-based messaging limits | normative |
| S7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/messaging-limits` | Messaging Limits | WhatsApp Business Platform | Reflects the Oct 2025 move to portfolio-level limits (see S9) | normative |
| S8 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-categorization` | Template categorization | WhatsApp Business Platform | References the **9 April 2025** categorization change | normative |
| S9 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog` | WhatsApp changelog | WhatsApp Business Platform | Dated entries 2024–2025; says MM API changes are logged separately | normative |
| S10 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/user_preferences` | `user_preferences` webhook reference | WhatsApp Cloud API (webhooks) | Requires `whatsapp_business_management` per S11 | normative |
| S11 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview/` | WhatsApp webhooks | WhatsApp Cloud API (webhooks) | Field table only; links to per-field references | normative |
| S12 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/overview` | Template fundamentals | WhatsApp Business Platform | No version stated | normative |
| S13 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers` | Business phone numbers | WhatsApp Cloud API | Returns `quality_rating`; defers status values to the API reference | normative |
| S14 | `https://www.facebook.com/business/help/896873687365001` | About Your WhatsApp Business Phone Number's Quality Rating | Meta Business Help Center | — | **normative page, body not retrievable.** A fetch returned only the title; the article is behind client-side rendering |
| S15 | search-index summary of S9 + S12 on "business portfolio pacing" | — | WhatsApp Business Platform | — | **observational** — no dedicated pacing page located |

S14's substance is reported below **only** as observational, flagged inline. It is Meta's own page, so the
claims are probably right; I could not read them, so this report does not treat them as established.

## 2. The rules

### 2.1 Opt-in — what Meta requires

The rule is short and the burden is entirely on the business. Per S1 and S5, a business may contact a person on
WhatsApp only when **both** conditions hold: the person gave the business their mobile number or username, **and**
the person gave opt-in permission confirming they wish to receive subsequent messages or calls from that business.
S5 words the consent as confirming the person "wish[es] to receive subsequent messages or calls from you."

Two content requirements, from S1:

1. The request must **clearly state that the person is opting in to receive communication from the business**.
2. The request must **clearly state the business's name**, so the person knows whose messages they are agreeing to.

**Where consent may be collected is the business's choice.** S1 gives examples rather than an allowlist: SMS, a
website, a phone call through an IVR flow, and in person or on paper (a signed physical document). S1 adds that
opt-in "can be general and not specific to WhatsApp, as long as businesses comply with all local laws" — so a
general marketing consent can cover WhatsApp, if local law permits.

**Legal responsibility sits with the business, not Meta and not the platform.** S1: it is up to businesses to
determine the method of opt-in and to ensure it complies with applicable law, including giving required notices
and obtaining required permissions. S5 uses the word **"solely responsible."** S5 also requires the business to
secure all necessary notices, permissions and consents to collect, use and share people's information, including
a published privacy policy.

Meta's stated best practices (S1, echoed in S5): obtain opt-in covering the **categories** of message you will
send (order updates, offers, product recommendations); obtain a **separate opt-in per category**, which S1 frames
as reducing the risk of being blocked for unsolicited messages; obtain a **separate opt-in before calling**; give
clear opt-out instructions per category and honour them; keep opt-in and opt-out flows clear and intuitive;
communicate the value of the messages; and monitor quality ratings especially when rolling out a new opt-in
method.

### 2.2 What Meta does *not* say about opt-in — stated plainly

This matters more than the rules, because it is where a documentation writer is tempted to invent.

- **No record-keeping requirement is stated.** Neither S1 nor S5 names a retention period, a required record
  format, or any field (timestamp, source URL, IP, wording shown) that a business must keep. Meta does not ask for
  proof of consent on any schedule, and does not describe an audit in which it would be produced.
- **No explicit list of insufficient opt-in methods is published.** S1 states requirements and says methods
  meeting them are policy-compliant. It does **not** publish a "these do not count" list — so a claim that
  purchased lists, scraped numbers, pre-ticked boxes or "number given for delivery therefore consented to
  marketing" are specifically disallowed **cannot be sourced to S1 or S5 as a named prohibition**. What *can* be
  sourced is the positive rule: consent must confirm the person wishes to receive subsequent messages from that
  named business. A number collected for another purpose, with no such confirmation, does not satisfy the stated
  rule. That is the honest framing; anything stronger is inference.
- **No wording template.** Meta gives no sample opt-in sentence that is deemed compliant.
- **No verification.** Nothing in S1, S5 or the API lets a business check, or Meta confirm, that a given recipient
  has opted in. Opt-in is unenforced at send time and enforced after the fact through user feedback.

### 2.3 The per-user marketing message cap

S2 is the only normative page on this and it publishes **no number**.

Meta's rule, per S2: "WhatsApp may limit the number of marketing template messages" a user receives from any
business in a given period of time, when that user is less likely to be receptive and engage. Two decision inputs
are named:

- a **dynamic view of the user's recent marketing-message read rate**, and
- **how many messages the user currently has in their inbox** from friends, family and businesses.

The limit **adapts automatically** with recent engagement: during periods of lower read rate or heavier inbox
activity a user may receive fewer marketing messages. S2 frames the trade as preserving a business's ability to
reach people "when they are most engaged."

Counting and exclusions, per S2:

- **Each marketing template message delivered counts** toward the user's limit.
- If the user **replies** to a marketing message, a 24-hour customer service window opens, and marketing messages
  sent inside that window **do not count**.
- The cap is **per WhatsApp user across all businesses** — S2 says "from any business," so it is not a per-sender
  allowance a business can reason about from its own send volume.
- **Not active** for messages sent from a business number in the **European Economic Area, United Kingdom, Japan
  or South Korea**, nor to users in those countries.
- **United States:** WhatsApp "doesn't currently deliver" marketing template messages to users with US phone
  numbers (+1 with a US area code); such sends error. S2 refers to a cutover date without stating it.

**How a business sees the limit: it does not.** S2 describes no API field, no WhatsApp Manager view, and no
webhook that reports a user's limit or remaining allowance. The only signal is the failure after the fact. This
is a documented absence, not a gap in my research.

### 2.4 Frequency capping and how Meta decides

Three distinct mechanisms, often conflated. Keeping them apart is the single most useful thing a Lynomia article
can do.

| Mechanism | Scope | Decided by | Visible to the business? | Source |
|---|---|---|---|---|
| Per-user marketing limit | one WhatsApp **user**, across all businesses | that user's read rate + inbox volume | No. Only error 131049 after a send | S2 |
| Messaging limit (tiers) | the **business portfolio**, shared by all its phone numbers | verification, volume of high-quality delivered sends, quality rating | Yes — tier value in WhatsApp Manager / API | S7 |
| Throughput / rate limits | API call and message rate | platform capacity | Via errors 130429, 80007, 4 | S4 |

The messaging limit is defined in S7 as "the maximum number of unique WhatsApp user phone numbers your business
can deliver messages to" **outside a customer service window**, within a **moving 24-hour period**. It is
calculated and set at **business portfolio** level and shared by every business phone number in the portfolio
(S7) — a change dated **8 October 2025** in S9, which also raised the initial scaling increase to 2,000.

A fourth, newer mechanism is relevant to campaigns specifically and is **poorly documented**: S9's entry dated
**8 December 2025** adds "business portfolio pacing," described as "a new template message delivery batching
mechanism" that "allows time to gather feedback on any template sent as part of a large-scale messaging
campaign." S12 separately defines "template pacing" as "A process that allows time for WhatsApp users to provide
feedback on message templates," and says a `message_status` property appears in send responses **only** when the
template being sent is being paced. **I could not locate a dedicated page for either** — S15, observational. The
practical consequence a campaign user would feel (a large send trickling out rather than going at once, or
messages withheld pending feedback) is therefore **not documented in a citable form**, and Lynomia must not
assert a mechanism it cannot source.

### 2.5 Marketing opt-out as a platform feature — the thing Lynomia is missing

Independently of the cap, WhatsApp gives users a first-class way to stop one business's marketing messages, and
gives the business an API surface for it. Per S10:

- The `user_preferences` webhook fires when a user **stops** marketing messages from the business, or **resumes**
  them. It does **not** fire for "Interested" / "Not interested" feedback given through the Offers and
  announcements setting.
- Payload: `changes[].field` = `"user_preferences"`; `changes[].value.user_preferences[]` carries `wa_id`,
  `category`, `value`, `detail` and a Unix `timestamp`.
- `category`: `marketing_messages` is the only value the page lists.
- `value`: **`stop`** or **`resume`**.
- `detail`: "User requested to stop marketing messages" / "User requested to resume marketing messages".

And per S4, error **131050** — "This recipient has chosen to stop receiving marketing messages on WhatsApp from
your business" — with the stated solution: **do not retry**, and subscribe to the `user_preferences` webhook to
track opt-outs and resumes.

Notably, S10 **does not state the business's obligation**: it does not say the business must stop sending
marketing after a `stop`, and gives no guidance on whether or when sending may resume after a `resume`. The
obligation comes from S5 instead ("respect any request to block, discontinue or opt out, including removing the
person from your contacts") and from S1 ("honor these requests"). That split is worth recording: the webhook
reference is silent on duty, the policy is not.

### 2.6 Block and report, and what blocking does

Per S5: users can **block** or **report** a business, and Meta's systems "may limit a business's message or call
volume based on that feedback." Per S1, people can share feedback with WhatsApp, stop receiving marketing messages
from individual businesses, block a business, or report it; WhatsApp "may rate-limit businesses whose quality stays
low for a sustained period" and may evaluate user feedback to flag violations. S5 also says Meta may review opt-in
flows **reactively**, including through user feedback — so a block can trigger scrutiny of how consent was
obtained, not only of the message.

**What Meta does not state anywhere I could read:** that a block hard-blocks future sends from the business to
that user, or what error a send to a blocking user returns. No normative page I fetched says "messages to a user
who blocked you fail with code X." The nearest documented recipient-level refusals are 131026 ("Unable to deliver
message", attributed to a non-WhatsApp number, unaccepted terms, or an outdated client) and 131050 (marketing
preference). **Do not write that blocking produces a specific error code.** What is sourced is weaker and
different: blocking is a **quality and enforcement signal** that feeds rate limiting and policy review.

S14 is the page that would answer the mechanics. Its body was not retrievable. A search-index summary of it
reports (**observational, unconfirmed**): the rating reflects messages recipients received over the past 7 days;
states are Green (high) / Yellow (medium) / Red (low); block reasons a user can choose include "No Longer
Needed," "Didn't Sign Up," "Spam," "Offensive Messages," and "No Reason"; a Red rating produces a **Flagged**
status that blocks messaging-tier upgrades; recovery to medium or high within 7 days returns the status to
Connected; and a number Flagged for 7 days has its limit decreased by one level. Every one of those should be
verified against S14 directly before it reaches an article.

What S13 (normative) does confirm: the API returns a `quality_rating` field with values including `GREEN`, `NA`
and `UNKNOWN`; "Business phone numbers have a status, which reflects their quality rating and current messaging
limit"; and a number "must have a status of 'connected' in order to send and receive messages via the API." S13
does **not** define the rating values, does not say what the rating is based on, and does not define FLAGGED or
RESTRICTED — it defers to S14 and the API reference.

Template-level quality is separately documented. S12 lists the WhatsApp Manager template quality states:
In-Review, Rejected, Active – Quality pending, Active – High Quality, Active – Medium Quality, Active – Low
Quality, Paused, Disabled, Appeal Requested. Medium and Low are described as negative feedback from multiple
customers or low read rates, with a risk of pausing or disabling; **Paused** is "paused due to recurring negative
feedback from customers, or low read-rates" and cannot be sent; **Disabled** is "disabled due to recurring
negative feedback from customers" and cannot be sent. S12 gives **no thresholds and no durations** for either.

### 2.7 Messaging Policy prohibitions most relevant to a business messaging platform

From S5 (last updated 23 September 2026):

- **Templates are mandatory for business-initiated conversations.** You may initiate conversations only with
  approved message templates, used only for their designated purpose; outside the 24-hour customer service window,
  only templates may be sent.
- **Prohibited businesses and content:** illegal products or services; criminal activity; deceptive or misleading
  business models; firearms; drugs; multi-level marketing; dating services; adult products and services; real
  money gambling; payday loans, peer-to-peer lending, debt collection, bail bonds.
- **Political and government:** political parties, politicians, candidates and campaigns are **prohibited**.
  Government entities are permitted **only through a Solution Provider**.
- **Restricted (Regulated Verticals):** alcohol, over-the-counter drugs, and online gambling/gaming are allowed
  only in listed countries, only on the Business **Platform** (not the Business App), and **never to people under
  18**.
- **Conduct:** do not "confuse, deceive, defraud, mislead, spam, or surprise people with your communications." No
  impersonation. No discrimination. No offensive content including sexually explicit material. **Do not share
  information from one customer's chat with another customer.**
- **Opt-out duty:** respect any request to block, discontinue or opt out, **including removing the person from
  your contacts**.
- **Scale:** operating a service that messages people at scale in an unauthorized manner gives Meta the right to
  limit or remove access.

The **Commerce Policy is now part of this same page.** `www.whatsapp.com/legal/commerce-policy` 301-redirects to
S5. Any Lynomia article or link pointing at the old Commerce Policy URL is stale but still lands correctly; any
article describing them as two separate documents is now wrong.

### 2.8 Consequences of violation — Meta's own escalation description

S6 is the page to cite, and it is unusually concrete. Its order, in Meta's own framing:

1. **Warning.** "Initially, WhatsApp Business Accounts will get a warning with information on the policy they
   violated."
2. **Restrictions that "gradually increase in duration."** S6's own examples:
   - a **1- or 3-day** block on marketing, utility and authentication templates, and on adding phone numbers;
   - a **5-, 7- or 30-day** block on sending any messages, and on adding phone numbers;
   - an **account lock** — "an indefinite block on sending any messages; can only be removed via an appeal."
3. **Permanent disablement** from the WhatsApp Business Platform, if the business "doesn't make changes after
   multiple warnings and feature limits or blocks."

**Immediate offboarding, no ladder,** for severe harm: S6 names child exploitation, scams, terrorism and illegal
drug sales.

Triggers named by S6: repeated violations of the Business Messaging Policy, Commerce Policy or Business Terms of
Service; specifically **spam**, **template misclassification**, and high-risk categories (adult content, alcohol
and tobacco, drugs, gambling, unsafe supplements); and **excessive negative user feedback**, which "may lead to
limits or offboarding."

Notification, per S6: Business Support Home in Meta Business Suite / Business Manager carries violation detail;
the Business Manager Notifications Center and a WhatsApp Manager banner surface it; **email goes to all Business
Manager admins** (so admin contact details must be current); and the **`account_update` webhook** sends
real-time notices including restriction type and duration where applicable. S11 confirms `account_update` covers
"policy or terms violations, offboarding, reconnection, or when it is deleted."

Appeals, per S6: in Business Support Home select the WABA, select the violation, **Request Review**, enter detail,
submit; the item moves to **In Review**; decisions "typically take 24 to 48 hours"; outcomes are **Unchanged** or
**Reversed**, and a reversal restores the account's prior status. S6 warns "Not all spam violations might be
appealed."

Two gaps in the ladder worth flagging. First, **S6 does not list template rejection or portfolio-level restriction
as enforcement actions** — those live in S8 instead. Second, S6 explicitly says it does **not** cover messaging
limits based on quality rating. So the full consequence picture requires three pages (S6 + S8 + S14), and no
single Meta page assembles it.

S8's own escalation, for businesses that consistently classify marketing templates as utility: **warning** (written,
to WABA admins) → **rate limiting** (utility messages capped in a rolling 24-hour window for **at least 7 days**;
marketing and authentication unaffected) → **utility restriction** (approved utility templates recategorized to
marketing, utility template creation and category review disabled, **7 days**, **30** for repeat violations) →
**portfolio-level restriction** (the same measures across all WABAs in the portfolio, **30 days**). Reported by
email and `account_update`.

And from S5, the ultimate consequence: if Meta terminates an account for violations it "may prohibit the
organization from all future use of WhatsApp products," and Meta acts "as determined by us in our sole
discretion," using automated processing plus human review. S5 states no step-by-step ladder of its own — it lists
available actions without ordering them. S6 is the only page that orders them.

## 3. Error codes and failures

Every row is quoted from S4 unless noted. S4 marks `error_subcode` **deprecated** and lists no subcodes, so the
subcode column is `not stated` throughout. HTTP status is given by S4 only for the Marketing Messages API table.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| 131049 | not stated | "This message was not delivered to maintain healthy ecosystem engagement." | The per-user marketing cap withheld this message from this one recipient | Wait **at least 24 hours** before resending; resending sooner "will likely fail again" | Nothing — the message is not delivered | S4, S2, S3 |
| 131050 | not stated | "This recipient has chosen to stop receiving marketing messages on WhatsApp from your business." | The user opted out of this business's marketing | **Do not retry.** Subscribe to the `user_preferences` webhook to track opt-outs and resumes | Nothing | S4, S10 |
| 131048 | not stated | "Message failed to send because there are restrictions on how many messages can be sent from this phone number." | A sending restriction on the number | Check quality status in WhatsApp Manager; review template limits and template quality | Nothing | S4 |
| 131064 | not stated | "Message failed to send because this account has reached its messaging limit due to template classification violations." | Enforcement from S8's ladder | Review template classifications; "the restriction lifts automatically after the enforcement period" | Nothing | S4 |
| 131063 | not stated | "Your template is categorized as Marketing, but marketing templates are currently disabled for your Cloud API configuration." | Marketing templates switched off for this Cloud API config | Use the Marketing Messages API, or re-enable marketing templates on Cloud API by setting the flag to false | Nothing | S4 |
| 131056 | not stated | "Too many messages sent from the sender phone number to the same recipient phone number in a short period of time." | Per-pair rate limit | Wait and retry for that recipient; other recipients unaffected | Nothing | S4 |
| 131047 | not stated | "More than 24 hours have passed since the recipient last replied to the sender number." | Outside the customer service window | Send a template message instead | Nothing | S4 |
| 131026 | not stated | "Unable to deliver message." | Reasons listed: recipient number not on WhatsApp, terms not accepted, or an outdated client | Have the user confirm they can message your number, accept the latest terms, update WhatsApp; use another channel | Nothing | S4 |
| 131050 vs blocking | — | — | **No code is documented for "the user blocked you."** See §2.6 | — | — | — |
| 130497 | not stated | "The WhatsApp Business Account is restricted from messaging to users in certain countries." | Country restriction for the business category | Check the Messaging Policy for countries allowed for your category | Nothing | S4 |
| 131031 | not stated | "The WhatsApp Business Account associated with the app has been restricted or disabled for violating a platform policy" | WABA-level enforcement | Review the Policy Enforcement document; the Health Status API may explain the lock | Nothing | S4 |
| 368 | not stated | "The WhatsApp Business Account associated with the app has been restricted or disabled for violating a platform policy." | Same, Graph-API-shaped | Review the Policy Enforcement document | Nothing | S4 |
| 132015 | not stated | "Template is paused due to low quality so it cannot be sent in a template message." | Template paused on quality | Edit the template to improve quality, retry once approved | Nothing | S4 |
| 132016 | not stated | "Template has been paused too many times due to low quality and is now permanently disabled." | Template permanently disabled | Create a new template with different content | Nothing | S4 |
| 130472 | not stated | "Message was not sent as part of an experiment." | Recipient excluded by a marketing message experiment | See the Marketing Message Experiment section | Nothing | S4 |
| 130429 | not stated | "Cloud API message throughput has been reached." | Throughput ceiling | Retry later or reduce send frequency | Nothing | S4 |
| 80007 | not stated | "The WhatsApp Business Account has reached its rate limit." | WABA rate limit | Retry later or reduce request volume | Nothing | S4 |
| 4 | not stated | "The app has reached its API call rate limit." | App-level rate limit | Check Application Rate Limit in the App Dashboard | Nothing | S4 |
| 131045 | not stated | "Message failed to send due to a phone number registration error." | Number not registered | Register the number, then retry | Nothing | S4 |
| 132069 | not stated | "Flow is in throttled state and 10 messages using this flow were already sent in the last hour." | Flow throttle, **10/hour** | Correct the Flow | Nothing | S4 |
| 134100 | not stated | "You're only able to send marketing messages on this API." | MM API accepts MARKETING templates only | Send only MARKETING templates | Nothing | S4 — HTTP **400** |
| 131055 | not stated | "Only marketing template messages are supported" | Same constraint | Resend using a marketing template | Nothing | S4 — HTTP **400** |
| 134101 | not stated | "When you send a message from a template, the template syncing process can take up to 10 minutes to complete." | Template not yet synced | Wait ~**10 minutes** after creating a template, then retry | Nothing | S4 — HTTP **400** |
| 134102 | not stated | "Please check your eligibility status to ensure you are onboarded or contact Meta's customer support." | MM API eligibility | Check eligibility; if ONBOARDED and still failing, contact support | Nothing | S4 — HTTP **500** |
| 132018 | not stated | "There's an issue with the parameters in your template." | Parameter mismatch | Fix parameters, resend | Nothing | S4 — HTTP **400** |

**The capped-send wording, precisely.** A Lynomia article that quotes Meta must quote this and nothing else: the
code is **131049** and the text is **"This message was not delivered to maintain healthy ecosystem engagement."**
It does not mention marketing, does not mention a cap, and does not name the recipient as the cause. That
mismatch between the code's cause and its wording is the whole reason agents misread it. S2 adds the delivery
mechanics: the **messages webhook fires with status `failed` and error code 131049**; S2 gives **no error title
or message wording of its own**, and S3's only wording is a description, not a title.

**The retry penalty is documented and is easy to miss.** S2: repeated resend attempts within 24 hours to capped
users "may make further delivery attempts unavailable for up to 24 hours," returning 131049 — and this "doesn't
affect marketing sends to other users." S2 also warns that early retries "reduce the accuracy of campaign
delivery reports," and S3 repeats it: repeated retries "can artificially lower a perceived delivery rate." A
platform that auto-retries 131049 therefore both deepens the block and corrupts its own analytics.

## 4. Limits and numbers

Only numbers a source states. Every absent number is called out rather than guessed.

| Number | What it governs | Source |
|---|---|---|
| **No published number** | the per-user marketing message cap. S2 gives no cap, no threshold, no period length | S2 |
| 250 / 2,000 / 10,000 / 100,000 / Unlimited | messaging limit tiers; API returns values such as `TIER_250` | S7 |
| 250 | the messaging limit of a **newly created business portfolio** | S7 |
| 2,000 | delivered messages outside customer service windows, to unique numbers, within a **30-day moving period**, using high-quality templates — one of the scaling paths to tier 2,000 | S7 |
| 6 hours | how quickly automatic scaling raises the limit one level, once conditions are met | S7 |
| half the current limit in the last 7 days | the usage condition for automatic scaling above 2,000 | S7 |
| 24 hours | the moving window over which the messaging limit counts unique recipients | S7 |
| 24 hours | the customer service window opened by a user reply; marketing sent inside it does not count toward the per-user cap | S2 |
| at least 24 hours | minimum wait before resending to a user who hit the per-user cap | S2, S3, S4 |
| up to 24 hours | how long further delivery attempts may be unavailable after repeated early retries | S2 |
| 1 or 3 days | enforcement block on marketing/utility/authentication templates and on adding phone numbers | S6 |
| 5, 7 or 30 days | enforcement block on sending any messages and on adding phone numbers | S6 |
| indefinite | account lock; removable only by appeal | S6 |
| 24–48 hours | typical appeal decision time | S6 |
| at least 7 days | duration of the utility rate-limiting step for template misclassification | S8 |
| 7 days (30 for repeat) | duration of the utility restriction step | S8 |
| 30 days | duration of the portfolio-level restriction step | S8 |
| 60 days | window to review and appeal template category changes in Business Support Home | S8 |
| 1 day | normal notice before an approved utility template is recategorized to marketing — **instant after a warning** | S8 |
| up to 24 hours | template review time (In-Review state) | S12 |
| 10 messages/hour | Flow throttle threshold behind 132069 | S4 |
| ~10 minutes | template sync delay after creation (134101) | S4 |
| 15 characters | authentication template parameter limit | S8 |
| 20 characters | coupon code template limit, raised from 15 on **3 December 2025** | S9 |
| **Not stated** | any threshold for Green/Yellow/Red quality, any count of pauses before a template is disabled, any durations for template pause | S12, S13 |
| **Not stated** | conditions that **lower** a messaging limit. S7 describes raising only | S7 |

## 5. Version and deprecation notes

- **`error_subcode` is deprecated** on S4. Any Lynomia code, article or error taxonomy keyed on subcodes for these
  codes is building on a deprecated field.
- **8 October 2025** (S9): messaging limits became **business-portfolio-based instead of phone-number-based**, and
  the initial scaling increase rose to 2,000. Any article describing the messaging limit as a property of a phone
  number is stale. S7 itself is internally inconsistent here: its definition and scope sections say portfolio
  level, while its approval and denial sections still speak of "a business phone number's limit."
- **9 April 2025** (S8, S9): `allow_category_change` is **no longer supported** at template creation; a template
  submitted as UTILITY that WhatsApp determines is MARKETING is now simply approved as MARKETING.
- **8 December 2025** (S9): business portfolio pacing added — see §2.4 and the S15 caveat.
- **18 November 2024** (S9): marketing message **user preferences**, the `user_preferences` webhook and error
  **131050** were introduced. This predates the 2025 window but is the origin of the opt-out surface.
- **6 February 2024** (S9): per-user marketing template message limits introduced.
- **S5 last updated 23 September 2026**, and says Meta "may change the policy without notice," with continued use
  counting as consent. Any Lynomia article that paraphrases the policy needs a review date and a link, not a copy.
- **URL migration:** Meta has moved WhatsApp docs from `developers.facebook.com/docs/whatsapp/...` to
  `developers.facebook.com/documentation/business-messaging/whatsapp/...`. Old `docs/` URLs still resolve in
  places, but the register above uses the current paths. `business.whatsapp.com/policy` and
  `www.whatsapp.com/legal/commerce-policy` both 301 to `whatsappbusiness.com/policy/`.

## 6. Ambiguities and gaps

These are places where Meta's documentation does not answer the question. Recording the ambiguity is the
deliverable; resolving it by guessing is forbidden.

1. **The per-user cap has no number, no period, and no visibility.** S2 names the inputs and refuses to quantify
   anything. There is no way for a business to know a user's limit, remaining allowance, or how close a campaign
   is to triggering 131049. A campaign of any size can produce some 131049s and the business cannot predict how
   many.
2. **What blocking does to future sends is undocumented.** No page I read states that a block prevents delivery,
   or names an error for it. Only its role as a quality/enforcement signal is sourced (S1, S5). The temptation to
   write "blocked contacts cannot receive your messages" must be resisted — it is unsourced.
3. **No quality-rating thresholds.** S12 and S13 describe states without numbers. S14, the page that would
   quantify them, was not retrievable by fetch. Everything in §2.6's observational paragraph needs direct
   verification.
4. **The consequence ladder is split across three pages and no page assembles it.** S6 explicitly excludes
   quality-based limits; S6 omits template rejection and portfolio restriction, which are in S8; S5 lists actions
   without ordering them. There is no single Meta page a user can be sent to for "what happens if I violate."
5. **`user_preferences` states no obligation.** S10 does not say the business must stop sending after a `stop`,
   nor whether a `resume` restores permission to send. The duty is in S5/S1; the timing after a `resume` is
   nowhere.
6. **Business portfolio pacing has no locatable page.** Its user-visible effect on a large campaign — the exact
   scenario Lynomia's feature creates — is undocumented beyond one changelog sentence (S9) and one glossary line
   (S12).
7. **The US marketing cutover date is referenced but not stated.** S2 says sends to US numbers "will error after
   this date" without giving the date.
8. **No record-keeping standard for consent.** §2.2. A platform that wants to help its users be defensible has no
   Meta specification to implement against; it must choose its own, and should say so.
9. **S7 does not state what error the messaging limit returns.** 131048 is about "restrictions on how many
   messages can be sent from this phone number" (S4) and is the nearest candidate, but S7 never links the two.
   Treat the mapping as **unverified**.

## 7. What Lynomia users would ask

Questions this area produces for a support desk, each answerable from the sources above:

- "My campaign says 37 failed with 131049 — is my number blocked?" (No. §2.3, §3.)
- "Can I see which contacts are near the cap, or exclude them?" (No. §2.3 — Meta publishes nothing.)
- "How many marketing messages per month can I send to one contact?" (Meta publishes no number. §4.)
- "Why did my US contacts all fail?" (Marketing templates are not delivered to US numbers. §2.3.)
- "I'm in the EEA/UK — does the cap apply?" (Per-user limits are not active there. §2.3.)
- "A contact asked me to stop. What do I do?" (131050 / `user_preferences` `stop`; do not retry; §2.5.)
- "What exactly must my opt-in say?" (Business name + that the person is opting in to receive communication from
  it. §2.1.)
- "Is a number someone gave me at checkout enough to send a promotion?" (§2.2 — the honest answer, and its
  limits.)
- "Can I promote alcohol / gambling / a political campaign?" (§2.7.)
- "My template was paused. How long?" (Meta states no duration. §2.6, §4.)
- "I got a warning email. What happens next?" (§2.8 ladder.)
- "How do I appeal, and how long does it take?" (Business Support Home → Request Review; typically 24–48h. §2.8.)
- "Why did my utility template become a marketing template?" (§2.4/S8 recategorization and its ladder.)
- "Why is my messaging limit 250 and how do I raise it?" (§2.4, §4.)

## 8. What a Lynomia campaign article must tell a user before they send to thousands of people

This section answers the brief's second question. It is written against what Lynomia's campaign feature actually
does, per agent 038's report, and against the corpus as it stands.

**What the product does today.** A WhatsApp campaign is one approved template sent once, at a scheduled time, to
the union of chosen labels and shared audiences, resolved at send time
(`custom/app/models/custom/campaign_audience.rb:12-19`), dispatched by
`Whatsapp::OneoffCampaignService` (`app/services/whatsapp/oneoff_campaign_service.rb:15-40`) with per-recipient
outcomes recorded by `Custom::Whatsapp::OneoffCampaignService`
(`custom/app/services/custom/whatsapp/oneoff_campaign_service.rb:22-147`). Lynomia already classifies 131049 as
recipient-scoped and withdraws Retry for it (`custom/app/services/whatsapp/delivery_failure.rb:20-33`), which is
**correct against S2/S3** — those pages say early retries both fail again and corrupt delivery reporting.

**Where the corpus stands.** `custom/db/documentation/en/audiences-and-campaigns/whatsapp-campaigns.md` (182
lines) contains **no opt-in section, no policy section and no quality section**; `grep -i "opt-in\|consent"`
matches once, at line 136, and only to admit a product limitation ("Blocked contacts are not excluded, and there
is no opt-out list"). `custom/db/documentation/en/whatsapp-errors/whatsapp-error-131049.md` is good and largely
accurate, but it omits S2's retry penalty, the EEA/UK/Japan/South Korea exclusion, the US non-delivery rule, and
the two decision inputs; and its line "a message genuinely about one transaction belongs in UTILITY, which this
cap does not apply to the same way" is vaguer than S2 permits — S2's limit is on **marketing** template messages,
full stop.

**The eight things the campaign article must say.** Concretely, and in this order of usefulness:

1. **You need opt-in, and the burden is yours.** State the two conditions and the two content requirements from
   §2.1, name the permitted collection methods, and say plainly that Meta holds the business "solely responsible."
   Lynomia does not check opt-in and cannot; a campaign will send to anyone in the audience.
2. **Be honest about what Meta does not publish.** There is no required consent record, no required wording, no
   retention period and no Meta verification (§2.2). Recommend what Lynomia can defend — keep the date, the
   source, and the wording shown — and label it Lynomia's recommendation, not Meta's rule. Do **not** write a
   "these opt-ins are invalid" list as though Meta published one.
3. **Some sends will fail and you cannot predict how many.** Meta caps per-user marketing volume, publishes no
   number, names only read rate and inbox volume as inputs, and exposes no way to see a contact's remaining
   allowance (§2.3). A completed campaign with some 131049s is normal, not a defect. This is the single most
   support-load-reducing sentence in the article.
4. **Do not resend to a failed recipient for at least 24 hours.** Quote S2's penalty: repeated attempts inside 24
   hours can make further attempts unavailable for up to 24 hours and distort the campaign's own delivery
   numbers. Explain that this is why Retry is withdrawn on 131049, and link
   `whatsapp-errors/whatsapp-error-131049.md`.
5. **Geography changes the rules.** Marketing templates are not delivered to **US** numbers at all; per-user
   limits are **not active** in the EEA, UK, Japan and South Korea (§2.3). An audience spanning those regions
   behaves differently per contact, and the article must say so rather than implying one global behaviour.
6. **131050 exists and Lynomia does not yet handle it.** A user can stop a business's marketing messages; Meta
   returns 131050 and says do not retry, and signals it through the `user_preferences` webhook (§2.5). Nothing in
   this repository references 131050 or `user_preferences` — `grep -rn "131050\|user_preferences"` over `app`,
   `custom`, `config` and `lib` returns no product hits. The article must state the gap honestly: a contact who
   opted out at WhatsApp will keep being included in Lynomia audiences, each campaign will fail for them, and the
   business must exclude them manually. This is a product gap for Phase 5, not just a doc gap.
7. **Volume has consequences beyond this campaign.** Blocks and reports feed quality rating, quality gates tier
   upgrades, and excessive negative feedback can lead to limits or offboarding (§2.6, §2.8). Give the escalation
   from S6 in Meta's order — warning, increasing-duration restrictions, account lock, permanent disablement — with
   the real durations, and the appeal path with its 24–48 hour typical decision time. Say what Meta does **not**
   publish: no quality thresholds, no template-pause durations, and no documented delivery consequence of a block.
8. **Check the content against the policy before you build the audience.** Templates are mandatory for
   business-initiated sends; prohibited verticals are listed in §2.7; political campaigning is prohibited outright;
   alcohol, OTC drugs and gambling are country-restricted, Platform-only, and never to under-18s. Link S5 by URL
   with the review date rather than copying it, since Meta may change it without notice. Note that the Commerce
   Policy is now the same page.

**Two things the article must not say.** It must not state a per-user message cap number — none exists in Meta's
documentation. And it must not say that blocked contacts cannot receive messages or that blocking returns a
specific error — that is unsourced (§2.6, gap 2).

**Recommended placement.** Extend the existing `audiences-and-campaigns` section rather than adding a new one: a
new `campaigns-and-the-rules.md` (or a substantial section inside `whatsapp-campaigns.md`) for items 1–5 and 8,
with items 6 and 7 linking to a new `whatsapp-errors/whatsapp-error-131050.md` and the existing
`whatsapp-errors/whatsapp-quality-and-limits.md` (76 lines — thin for what §2.6/§2.8 now contain). The
contextual-help registry already has `whatsappQualityAndLimits` and `whatsappError131049`
(`app/javascript/dashboard/helper/documentationLinks.js:44,45,49`); a campaign-form key and a
`whatsappError131050` key would both be new.
