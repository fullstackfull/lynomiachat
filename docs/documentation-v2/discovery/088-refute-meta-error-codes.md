---
agent: 088
scope: Refutation of every Meta error-code, subcode and "what it means" claim in discovery reports 001–028 and in the whatsapp-errors corpus
confidence: high
sources_normative: 13
sources_observational: 3
---

# 088 — Refuting the Meta error-code claims

I re-fetched Meta's pages myself and compared them against the claims, rather than reading the reports and
scoring their internal consistency. Every verdict below rests on a page I rendered on **2026-10-13**. Where I
could not render a page, the row says `not checked` and I draw no conclusion from it.

## 0. Source register

| # | Source URL | Page title | Product | API/version context | Status |
|---|---|---|---|---|---|
| M1 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | WhatsApp error codes | WhatsApp Cloud API | states error titles "will eventually be deprecated"; no title column | normative |
| M2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/support/error-codes` | WhatsApp error codes (new tree) | WhatsApp Cloud API | same content as M1 under the migrated path | normative |
| M3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/per-user-limits/` | Per-user marketing template message limits | WhatsApp Cloud API | none stated | normative |
| M4 | `https://developers.facebook.com/docs/graph-api/guides/error-handling` | Handle Errors — Graph API | Graph API | none stated | normative |
| M5 | `https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/subscribed_apps/` | WABA `subscribed_apps` | Graph API | reference edge | normative |
| M6 | `https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/message_templates/` | WABA `message_templates` | Graph API | reference edge; per-method error tables | normative |
| M7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/` | Onboard WhatsApp Business app users (coexistence) | WhatsApp Business Platform | session payload `version: 3` | normative |
| M8 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/throughput` | Throughput | WhatsApp Cloud API | none stated | normative |
| M9 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/registration` | Registration | WhatsApp Cloud API | none stated | normative |
| M10 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers.md` | Business phone numbers | WhatsApp Business Platform | examples v25.0 / v15.0 | normative |
| M11 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/media` | Media | WhatsApp Cloud API | none stated | normative |
| M12 | `https://developers.facebook.com/docs/graph-api/reference/business/business_users/` | Business `business_users` | Graph API / Business Management | reference edge; per-method error tables | normative |
| M13 | `https://developers.facebook.com/docs/graph-api/reference/page/roles` | Page Roles | Graph API (Pages) | reference edge | normative |
| O1 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog.md` | WhatsApp changelog | WhatsApp Business Platform | entry dated 2023-05-23 | **observational** (a changelog, per program §6.2) |
| O2 | WebSearch `"131060" WhatsApp error code site:developers.facebook.com` | — | — | — | **observational** — establishes absence only |
| O3 | WebSearch `WhatsApp Business API error "80008"` | — | — | — | **observational** — returned only vendor help pages |
| X1 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/message-templates` | — | — | — | **HTTP 404 — does not exist** |

## 1. What I attacked

- Every numeric code, subcode, title and remedy in the error-code tables of reports **002, 004, 005, 006, 008,
  009, 010, 011, 012, 013, 014, 025** and the master register **028**.
- All five coded articles in the corpus: `custom/db/documentation/en/whatsapp-errors/whatsapp-error-{131042,131049,131053,131060,190}.md`
  and their Arabic twins, plus the code comments those articles inherit their meanings from
  (`app/services/whatsapp/media_upload_service.rb`, `app/services/whatsapp/providers/whatsapp_cloud_service.rb`,
  `custom/app/services/whatsapp/delivery_failure.rb`, `app/services/whatsapp/incoming_message_base_service.rb`).
- Report **028's §9 "BLOCKERS"** list, because it is the one document in the directory that proposes *striking*
  other agents' codes, and a false strike is more expensive than a false claim.
- The inverse case the brief asks for: codes asserted as undocumented that Meta does document.

**Reports that did not exist when I audited and are therefore not covered**: 015, 016, 017, 018, 019, 020, 021,
022, 023, 024, 026, 027 arrived mid-audit and I checked only the rows other reports cite from them (019/020 on
131052/131053); 001, 003, 007 I did not audit at all. Agents 049, 050, 080, 088–099 had written nothing.

## 2. Refutations

### 2.1 Report 028's §9 blocker list is wrong in at least twelve of its eighteen rows — `blocker`

**The claim.** 028 §9 lists codes "claimed by other agents that I could NOT verify — BLOCKERS", and states the
governing premise explicitly: *"'Could not verify' here means not present on any of S1–S12, which includes every
error-code reference Meta publishes for the four products."*

**Why it is wrong.** That premise is false. Meta publishes error codes in three places, not one: the error-code
reference pages (028's S1–S12), **per-method error tables on Graph API reference edges**, and **inline in product
documentation pages**. The second and third are equally normative and are exactly where agents 004, 009, 013 and
014 sourced from. 028 concedes the possibility in the same paragraph — *"most are plausibly on a Graph API
reference edge's own error list"* — and then grades them `blocker` anyway. It never fetched those pages.

I fetched them. Every quoted string below is verbatim from the page the original agent cited.

| Code | 028's §9 verdict | What the cited page actually prints | Source |
|---|---|---|---|
| `192` | blocker — "Not on S1–S12" | "Invalid phone number" (POST error table) | M6 |
| `200002` | blocker | "HSM Template creation failed" (POST) | M6 |
| `80008` *title text* | major — "publishes no such sentence" | "There have been too many calls to this WhatsApp Business account. Wait a bit and try again." — on GET, POST **and** DELETE | M6, M5 |
| `136024` | blocker | "calling the `request_code` endpoint returns HTTP 400 with error code `136024`"; the number is already verified | M10 |
| `137000` | blocker | "you will receive a status messages webhook with error code `137000`, notifying you of the failure and mismatch" | M10 |
| `283` | blocker | "That action requires the extended permission pages_read_engagement and/or pages_read_user_content…" | M13 |
| `415` | blocker | "Two factor authentication required… This could happen when accessing a 2fac-protected asset like a page that is owned by a 2fac-protected business manager." | M12 |
| `457` | blocker | "The session has an invalid origin" (Creating) | M12 |
| `104` | blocker | "Incorrect signature" (Reading, both pages) | M12, M13 |
| `370` | blocker | "Invalid call to update this page" (Creating) | M12 |
| `80001` *title text* | major — "the sentence is not on S10" | "There have been too many calls to this Page account. Wait a bit and try again." | M13 |
| `133016` numbers | minor — "do not present as reference-sourced" | "Up to 10 requests per business number in a rolling 72-hour window"; the API "prevents the number from being registered for the next 72 hours" | M9 |

Also confirmed on the same pages and never in doubt: `139000` "Blocked by Integrity", `613` "Calls to this api
have exceeded the rate limit.", `368` "The action attempted has been deemed abusive or is otherwise disallowed",
`131057` and `130429` (M8, with "can take up to 1 minute" and "During this time the number will not be usable on
our platform" stated verbatim).

**Impact.** 028 is the designated master auditor; `_ARBITRATION.md` and Phase 4's error taxonomy are being built
from its verdicts. Acting on §9 would strike twelve correctly-sourced, verbatim Meta codes from the register and
would brand six accurate agents as fabricators. The register in 028 §3 is good work; §9 must be rebuilt by
fetching each original agent's cited page, not by re-testing against a different page.

**Partly refuted, same row set.** `2061` / `2062` (claimed by 010): O1 prints them verbatim — *"Attempting to
send a paused template in a template message now returns error code `2061`"* — so 028's *existence* verdict is
wrong. 028's *separate* caution survives and is the better point: the On-Premises API is retired, and a
retired-product code in a user-facing article is worse than no code. Keep the caution, drop the "blocker".

**Survived from §9**: the `131060` title (§3 below) and 028's refutation of agent 002 (§2.8).

### 2.2 The corpus article for 131053 states a cause and a remedy that are not Meta's — `blocker`

**The claim.** `custom/db/documentation/en/whatsapp-errors/whatsapp-error-131053.md` (title "WhatsApp could not
fetch the file"): "`131053` means WhatsApp tried to **download a file from your installation and could not**. It
is a transport problem between Meta and whoever hosts your server" … "Meta's download path is rate limited per
destination network, so on shared hosting your installation can be throttled because of traffic that has nothing
to do with you." Remedy: check whether the file is large or slow, check Account Health, press Retry.

**Why it is wrong.** M1/M2 give 131053 one meaning: **"Unable to upload the media used in the message."** The
cause Meta names is an unsupported or mismatched media type, and the remedy is `error.error_data.details` on the
`messages` webhook plus inspecting the file's real MIME type (`file -I`) against the supported list. The
direction is inverted: Meta's code is about the business's media failing to upload, not about Meta failing to
fetch. M11 is the page that discusses downloads, and it says failures of Meta-issued media URLs return **HTTP
404**, with the remedy "get a new media URL and retry". M11 contains **no statement about rate limiting of media
downloads** — nothing about ASN, destination network, or fwdproxy. Nothing on M1, M2 or M11 documents a code for
"Meta could not fetch a business-supplied link".

**Provenance of the folklore.** The claim originates in a code comment, not in Meta:
`app/services/whatsapp/media_upload_service.rb:3-5` ("rate limited per destination ASN and returns intermittent
131053 errors when instances share a hosting provider") and `app/services/whatsapp/providers/whatsapp_cloud_service.rb:191`.
That comment's own `ref:` is `developers.facebook.com/docs/whatsapp/cloud-api/reference/media#upload-media` — a
page about the upload endpoint that states none of it. A code comment citing a page that does not support it,
promoted into user-facing help, is the exact failure mode the program's §6.2 exists to prevent.

**Impact.** A user whose send failed on a MIME mismatch is told to investigate their hosting provider. The
article also contradicts itself: it asserts Lynomia always uploads first and sends by media id, which would mean
Meta never fetches, which would make the failure it describes unreachable.

Agent 054 reached the same verdict independently (its C4/G1), and 019 §3 and 020 §3 both transcribe Meta's
meaning correctly. Three independent paths agree; the article is the outlier.

### 2.3 The corpus article for 131060 contradicts Meta's documented remedy — `blocker`

**The claim.** `whatsapp-error-131060.md`: the code covers "message types WhatsApp will not forward to a business
API: some interactive and system message types, and media WhatsApp itself could not process". What to do: "**Ask**
the customer." Limit: "**The content cannot be recovered**, by you or by support. WhatsApp did not send it."

**Why it is wrong.** M7 is the only Meta page that documents 131060, and it names exactly two circumstances,
both specific to **coexistence**: a WhatsApp user messaging the business *for the first time*, and a user on an
*unsupported companion device*. Meta adds that "the error typically resolves within a few seconds" and gives one
remedy: "If you receive this webhook, instruct the business to **check the WhatsApp Business app for the
message**." So the content *is* recoverable, in the place Meta names, and the article tells the reader the
opposite. The article's own cause list — unsupported message types — is Meta's **131051** ("Unsupported message
type", M1/M2), a different code. The word "coexistence" does not appear in the article.

**Impact.** The article's single instruction (ask the customer to resend) replaces Meta's single instruction
(look in the WhatsApp Business app). Lynomia's own code comment is more accurate than its documentation:
`app/services/whatsapp/incoming_message_base_service.rb:92-94` already says "coexistence companion-device syncs".
Corroborated by 054 (D3, D9, G2) and 005 ("not a request-time send failure").

### 2.4 The corpus article for 131049 contradicts Meta's remedy and invents a rationale — `major`

**Two separate refutations.**

*(a) The remedy.* The article: "**Nothing, for that message.** … Nothing you change about the message, the
template or the number makes Meta accept the same message to the same recipient." M1/M2 and M3 both state the
opposite remedy: "wait at least **24 hours** before resending the template message", because "resending sooner
will likely fail again". Meta's recommended action is a later resend; the article forecloses it. M3 adds the
escalation the article omits: repeated resends inside 24 hours can make "further delivery attempts to these users
… unavailable for up to 24 hours".

*(b) The rationale for withdrawing Retry.* The article: "every attempt is one more signal against your number's
quality rating". **M3 does not mention quality rating at all.** Its only stated consequence of early resending is
that it "can reduce the accuracy of campaign delivery reporting". The quality-rating claim traces to
`custom/app/services/whatsapp/delivery_failure.rb:5-7` and is repeated in a user-facing string; it has no Meta
source. The product behaviour may still be defensible — it is simply not Meta's reason, and must not be presented
as one.

*(c) A hedge that should be a fact.* The article: UTILITY "is a category this cap does not apply to the same way".
M3's scope is marketing template messages; it does not mention utility or authentication templates at all. The
vagueness is the agent's, not Meta's.

Report 006 transcribed Meta's remedy correctly ("wait **at least 24 hours** before resending that template"), so
the corpus and report 006 now contradict each other on the same code. 028 §12 and 054 §A found (a) too.

### 2.5 The corpus article for 190 asserts a causal chain Meta does not document — `major`

**The claim.** "`190` is Meta saying the credential is no longer accepted. The token expired, was revoked, **had a
permission removed**, or belongs to an app that changed." Worked example: an administrator removes a colleague
from the Meta business portfolio, "the token that colleague had authorised stops working".

**Why it is wrong.** M4 gives 190 one meaning: "Access token has expired." A *removed permission* is a different
code on the same page: `200–299` "API Permission" and `10` "API Permission Denied", both described as "Permission
is either not granted or has been removed." M1/M2 confirm the WhatsApp wording: 190 "Your access token has
expired." Folding permission loss into 190 merges two codes with two different fixes.

The worked example is worse: report 004 §3.1 establishes from M12 that removal from a business portfolio **is not
an API operation at all** and that Meta "does not document what happens to that person's tokens". The article
presents as a worked example a consequence Meta declines to state. Report 025 is correct that no Meta error names
a revoked permission — which supports the article's "Lynomia cannot tell you which permission was lost" and
refutes its "had a permission removed" in the same breath.

### 2.6 Report 010's §3 was written without Meta's error-code reference, and two of its rows are wrong — `major`

Report 010's source register (S1–S11) contains **no error-code reference page**. Its §3 error table is sourced
almost entirely to S10, which 010 itself classifies as **observational** (the changelog) — yet the table marks
only 132015 with a normative/observational note, leaving 132016, 132001, 2061 and 2062 looking equally
established. Two consequences:

**(a) `132016`'s remedy is the agent's, not Meta's.** 010: "What the business can do: **Edit and resubmit the
template**." M1/M2: 132016 is "Template has been paused too many times due to low quality and is now
**permanently disabled**", and the remedy is "**Create a new template with different content**." Telling an
operator to edit and resubmit a permanently disabled template sends them into a loop that cannot terminate. 010's
§2.5 shows how it got there — a different Meta page (template review) says to edit and resubmit a *disabled*
template — so this is also a genuine Meta-internal conflict that 010 could not see without M1/M2. Report 011
quotes Meta's remedy correctly from the same page I read.

**(b) `132001` is presented as a retired code when it has a current and much more common meaning.** 010: "the
code returned for paused **and** disabled templates **before** v17.0", remedy "Move off pre-v17 versions". M1/M2
give 132001's live meaning: "**The template does not exist in the specified language or the template has not been
approved**", remedy "Make sure your template has been approved and the template name and language locale are
correct." O1 does support 010's historical reading — "Attempting to send a paused template … using v17 or later
now returns error code `132015`" (dated 2023-05-23), and v17 is long past — so both are true, but an article
carrying only 010's version would hand the wrong remedy to every user hitting today's 132001, which is one of the
commonest template send failures. 028 §12 row 1 and 011 §3.1 both caught the conflation; neither caught (a).

### 2.7 Inverse refutation: codes said to be undocumented that Meta does document — `minor`

The brief asks for this case specifically. Report 012 §3 states: "**Not found anywhere in the register**: a
documented error code for a wrong header format at send, a wrong media type for a header, a carousel `card_index`
out of range, a button `index` that does not exist in the template, a coupon code over 20 characters, or an OTP
over 15 characters", and concludes "Lynomia's whatsapp-errors section **must not invent codes for these**."

Meta documents codes for the first two. M1/M2: `132012` "Variable parameter values formatted incorrectly" —
"The variable parameter values included in the request are not using the format specified in the template",
which is the send-time format failure; and `132000` for a parameter *count* mismatch. At creation time, report
005's own table (from Meta's template-creation errors) carries `2388047` "Message header format is incorrect".
012's sentence is correctly hedged to *its own* register and it defers to agents 005/011, so the finding is
minor — but the instruction it draws is wrong as written, and an orchestrator skimming §3 would adopt it.
The remaining four (carousel index, button index, coupon length, OTP length) I also could not find on M1/M2;
012's caution holds for those.

### 2.8 Smaller refutations

| # | Claim | Report | Why it is wrong | Severity |
|---|---|---|---|---|
| a | `131009` means "invalid `message_id` on a mark-as-read call" | 006 §3 | M1/M2 give 131009 generally: "One or more parameter values are invalid." 006 read it only on the mark-as-read page (its R8) and narrowed the meaning to that call. M6 shows the same code on template **creation**. An article built on 006's row would be wrong for the common case. 011 has the general wording | minor |
| b | `137000` — "What the end user sees: nothing — **pre-launch**" | 014 §3 | M10 shows 137000 arriving on a **status messages webhook** when a send's `recipient_identity_key_hash` does not match — a send-time failure on a live number, not a pre-launch registration problem. The code and meaning are right; the lifecycle placement would file it in the wrong article | minor |
| c | "`131053` has two different official meanings … Meta does not reconcile them" | 028 §6.1, §12 row 2 | Over-read. M1/M2 say the media "could not be uploaded for one or more reasons, **such as** an unsupported media type"; M11's "mismatched MIME type (`131053`) is a common error" is an *instance* of that, with the same remedy (`file -I`, check the supported list). One meaning, one remedy, a general page and a specific page. Report 019 handled it correctly as cause-of. Publishing it as a Meta self-contradiction would teach readers a conflict that is not there | minor |
| d | "Title as Meta words it: Mismatched MIME type"; a row for "HTTP 404" in an error-code table | 012 §3 | M1/M2 publish **no title column at all** for these codes, and "mismatched MIME type" is M11's prose about a cause, not a title. HTTP 404 is a transport status, not a Meta error code. 028 §0 states the no-title fact correctly and should be applied to 012's table | minor |
| e | Code `200` presented with a single meaning ("permissions error" / missing business asset access) | 002, 013, 014 | Meta publishes two different meanings on its own pages: M1/M2 say 200 is "**No access token was provided**" (and that other endpoints return 190 or 104 instead), while M5, M6, M12 and M13 all print 200 as "**Permissions error**". Both are normative; the fixes are unrelated. None of 002/013/014 records the conflict. Already raised as `M-19` in `_ARBITRATION.md` by 001/003/004 — this is independent corroboration, and the arbitration must resolve it before any article says "error 200 means…" | major |
| f | "The access-token debugging and error-handling page 404s at the documented path", used to defer the whole 190 family | 002 §3 | M4 rendered for me today, carries the full 190 subcode family, and was read the same day by 004 (its S2) and 025 (its S1). The omission in 002 is real and was avoidable. 028 found this too; I confirm it independently | minor |
| g | `368`'s title given as "The action attempted has been deemed abusive or is otherwise disallowed" without qualification | 004, 009 | Accurate for M6 and M12. But M4 names 368 "**Temporarily blocked for policies violations**" and M1/M2 gloss it as a WABA restricted or disabled for a policy violation. Three normative pages, three glosses, one code. Presenting any one as "the" title repeats the mistake 028 §0 warns about | minor |

## 3. Survived

These I attacked and could not break. This list matters as much as the refutations.

- **Report 011's error table — the most accurately transcribed in the directory.** I re-read M1/M2 against
  132000, 132001, 132005, 132007, 132012, 132015, 132016, 132068, 132069, 100, 131008, 131009, 131047, 131049,
  131050 and found every `details` string and every remedy verbatim, including the remedies 010 got wrong.
  011's §3.1 distinction between 132000 (count), 132012 (format) and 132001 (identity) is Meta's own and is the
  right basis for Lynomia's copy. Its flag that 132001 conflates two causes is correct and important.
- **Report 004's Graph API table.** I expected the long tail (283, 415, 457, 370, 104, 613, 80001) to be
  folklore. All of it is verbatim on M12 and M13, the pages 004 cited. All seven subcodes (458, 459, 460, 463,
  464, 467, 492) and their titles match M4 exactly, including 492's "User associated with the Page access token
  does not have an appropriate role on the Page." Its separation of normative meaning from inferred
  event→subcode mapping is the correct treatment. One genuine weakness: M4 attaches the subcodes to
  authentication generally and says code `102` also takes them, so rendering them as `190 | 458` rows binds them
  more tightly to 190 than Meta does — 025 states this limit correctly and 004 does not.
- **Report 013's coexistence codes.** `131060` and `2593109` are on M7 exactly as claimed, including the
  circumstances and the "check the WhatsApp Business app" remedy, and `80008`'s quoted sentence is verbatim on
  M5. The one thing that fails is 028's catch: M7 gives 131060 **no title**, so "Unsupported messages webhook"
  is the webhook's name, not the code's title. 013 is otherwise the best-sourced report on this code.
- **Report 014's registration and throughput codes.** `136024` (HTTP 400 from `request_code`, already verified),
  `137000`, `133016` (10 requests / rolling 72 hours / blocked 72 hours), `131057` and `130429` are all verbatim
  on M9, M10 and M8, with 014's "up to 1 minute" matching M8's "can take up to 1 minute". Only the lifecycle
  placement of 137000 is wrong (§2.8b).
- **Report 009's creation codes.** `100`, `131009`, `80008`, `192`, `200`, `368`, `200002`, `139000`, `190` are
  all on M6, in the methods 009 assigns them to (190 on GET and DELETE but not POST, exactly as 009's table
  implies). One blemish: the `80008` cell's "consistent with 100 templates/WABA/hour" is 009's inference sitting
  inside a "what it means" column.
- **Report 006's deprecation finding.** M1/M2 confirm it and go further than 006 did: there is no title column
  at all, and the page says not to build error-handling logic on titles. 006's conclusion that a pipeline keeping
  only `code` + `title` discards the one field Meta tells you to read is right.
- **Report 008's position that pricing and categories produce no numeric codes.** I looked for one on M1/M2 and
  found none. Its string-valued table is the right shape for the area.
- **Report 005's `2388103` finding** — one code with eleven published variants, discriminated only by the
  `details` string Meta says not to depend on. I could not break it and it is the sharpest design constraint any
  report in this scope produced.
- **Report 028's §3 register and §0 structural finding.** The register's rows that I spot-checked (131026,
  131042, 131047, 131049, 131050, 131051, 131052, 131053, 131056, 131060, 132001, 132015, 132016) all match
  M1/M2/M7/M11. The "no titles are published" finding is correct and should govern every other table.
  §9 is the part that fails.
- **The corpus article for 131042.** Its substance holds: M1/M2 give "There was an error related to your payment
  method", and the causes Meta names (payment account not attached, credit line over limit, unset timezone or
  currency) match the article's billing story. Two small distortions, both `minor`: the article says "a currency
  that does not **match** the account" where Meta says **unset** timezone or currency; and "it stops every paid
  message on that number rather than one" is a scope Meta does not state. 054's finding that "Retry stays
  available" is false after one day is a product-side defect, not an error-code defect, and I leave it there.

## 4. Not checkable

- **`138024`** (014) and **`132021`** (011). I did not render Meta's health-status page or 011's R8, so I neither
  confirm nor refute them. 028's instinct that 138024 may be a `health_status` value rather than an API error code
  is worth testing, but it is untested by both of us. What is needed: fetch
  `/documentation/business-messaging/whatsapp/support/health-status.md` and 011's R8 and quote the row.
- **`240`** (004). Absent from M12; 004 sourced it to its S3 (`/docs/graph-api/reference/user/permissions/`),
  which I did not fetch. 004 itself says the code is "listed only, no description given", so there is nothing to
  publish either way.
- **Reports 001, 003, 007, 015–024, 026, 027** arrived during or after my audit. Their error-code claims are
  **not checked**. Given that 028's §9 misgraded twelve rows by testing against the wrong pages, the same
  verification — fetch the page the agent cited, quote the line — must be run over them before Phase 4 freezes
  the taxonomy.
- **Whether Meta's per-endpoint error tables are version-stable.** M5, M6, M12 and M13 are labelled v26.0. I
  cannot tell from them whether a code listed on a v26.0 edge was present at the version Lynomia calls, and Meta
  does not say. Recording the ambiguity rather than resolving it.
- **The three Arabic error articles' meanings.** I read the EN originals and the AR files' line counts only; I
  did not assess whether the AR text carries the same (wrong) causal claims. That is agent 094's scope, but note
  that every refutation in §2.2–2.5 presumably applies twice.
