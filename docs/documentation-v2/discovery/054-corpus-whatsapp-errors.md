---
agent: 054
scope: whatsapp-errors corpus section (14 EN + 14 AR) analysed as the pattern for the Meta error corpus: structure, evidence, code coverage vs classification, canonical article shape
confidence: high
---

# 054 — Corpus: `whatsapp-errors`

Read-only. Every repository claim below carries `path:line`. Claims about what **Meta** does are marked
`unverifiable (Meta)` because this brief is repository-only; they are routed to the Meta agents (005, 010, 014, 017,
018, 019/020, 025, 026, 028), not resolved here. Nothing was run (no rails, rake, rspec, pnpm); the SEO audit was
not executed, so front-matter lengths below are measured by hand.

The section is 14 articles per locale. Five are "code articles" (131049, 131042, 131053, 131060, 190), nine are
"symptom articles" (no code). The headline is that the section is **two very good code articles, three weak ones,
and nine mostly sound symptom articles**, and that quality tracks one variable closely: whether the repository
holds a record of the failure having been *seen*.

The sharpest facts, before the template sections:

1. `Whatsapp::DeliveryFailure` classifies **two** codes, not five (`custom/app/services/whatsapp/delivery_failure.rb:28-31`).
   `01-current-system.md` §7 and charter §1.2 say five. See §7.
2. Only those two can ever link from the failed-message UI to their article (`MessageError.vue:70-77` needs
   `props.deliveryFailure`, which the server sends only for classified codes, `delivery_failure.rb:64-68`). The other
   twelve articles have **no in-product entry point at all**.
3. The 190 article describes a mechanism the code does not implement for sends, and a banner that is not where it
   says (§3 E1-E3). The missing mechanism is the defect already logged as SHO-64 (`docs/p7/00-discovery-findings.md:833`).
4. The 131060 article describes an "empty" message; the dashboard shows "This message is unsupported. You can view
   this message on the WhatsApp app." (`bubbles/Unsupported.vue:22-23`, `en/conversation.json:79`).
5. The Arabic articles quote UI labels that the Arabic locale files do not contain (§6).

---

## 1. Inventory

Files: `custom/db/documentation/{en,ar}/whatsapp-errors/<key>.md`. Category: slug `whatsapp-errors`, position 55,
icon `alert-triangle` (`custom/db/documentation/manifest.yml:57-65`). Words are body words (front matter excluded,
whitespace-split; Arabic clitics attach to words, so AR counts run 0.73-0.85 of EN by construction). Lines in
parentheses are file lines.

| key | EN file | AR file | title (EN) | pos | EN words | AR words |
|---|---|---|---|---|---|---|
| whatsapp-error-131049 | yes (70) | yes (65) | Error 131049 — WhatsApp refused the message for this one person | 10 | 529 | 433 |
| whatsapp-error-131042 | yes (62) | yes (58) | Error 131042 — the WhatsApp Business account cannot be billed | 20 | 463 | 393 |
| whatsapp-error-131053 | yes (58) | yes (53) | Error 131053 — WhatsApp could not fetch the file | 30 | 405 | 321 |
| whatsapp-error-131060 | yes (55) | yes (50) | Error 131060 — an incoming message WhatsApp will not hand over | 40 | 360 | 290 |
| whatsapp-error-190 | yes (65) | yes (59) | Error 190 — the WhatsApp access token is no longer valid | 50 | 437 | 361 |
| whatsapp-number-status | yes (62) | yes (58) | Flagged, restricted, banned — what the number's status means | 60 | 533 | 436 |
| whatsapp-quality-and-limits | yes (76) | yes (72) | Quality rating and messaging limits | 70 | 557 | 460 |
| whatsapp-display-name | yes (52) | yes (52) | The display name was not approved | 80 | 330 | 264 |
| whatsapp-nothing-arrives | yes (66) | yes (61) | Nothing is arriving from WhatsApp | 90 | 522 | 423 |
| whatsapp-reconnect-a-number | yes (64) | yes (62) | Reconnect a WhatsApp number | 100 | 529 | 442 |
| whatsapp-number-already-connected | yes (56) | yes (49) | "Channel already exists for this phone number" | 110 | 391 | 285 |
| whatsapp-contact-info-requests | yes (52) | yes (50) | A contact information request was refused | 120 | 455 | 375 |
| whatsapp-business-scoped-contacts | yes (57) | yes (50) | Business-scoped WhatsApp contacts, and what cannot be sent to them | 130 | 391 | 315 |
| whatsapp-find-a-failed-message | yes (80) | yes (75) | Finding the conversations where a message failed | 140 | 571 | 463 |
| **total** | 14 | 14 | | | **6,473** | **5,261** |

Facts about the set, measured: exact EN/AR key parity (the corpus spec enforces it,
`spec/custom/services/documentation/content_seeder_corpus_spec.rb:25-27`); zero broken internal links in either
locale (every `](key)` target exists in the 63-key corpus, scripted check); zero images in 28 files; 8 of 14 articles
contain a table; **the only article outside the section that links in is `whatsapp/whatsapp-troubleshooting`, and it
links to all 14** (`custom/db/documentation/en/whatsapp/whatsapp-troubleshooting.md:101-122`) — the section has no
index of its own, the hub is a hand-written paragraph in a different section.

---

## 2. Per-article verdict

`Evidence` points to the §3 row ids.

| key | verdict | reason | evidence |
|---|---|---|---|
| whatsapp-error-131049 | EXPAND | Lynomia mechanics are code-verified and the failure was observed; add Meta source and Meta's verbatim title, reconcile with the in-product "wait at least a day" copy, tell the reader the campaign table shows `Code 131049` | A1-A8 |
| whatsapp-error-131042 | EXPAND | Mechanics verified, observed; but "Retry stays available" is false after one day, and "the one that is yours to fix" is contradicted inside the section | B1, B2, B6 |
| whatsapp-error-131053 | REWRITE | The Lynomia half is accurate and specific (upload-first, fallback, timeout) but the code's definition is lifted from an upstream comment, a cause that re-creates the failure (the operator env switch) is missing, and it has no in-product link | C1-C6 |
| whatsapp-error-131060 | REWRITE | Describes UI that does not exist ("empty message"), attributes the code to message types with no evidence, omits the only evidenced cause (coexistence companion-device syncs), invents the worked example | D1-D6 |
| whatsapp-error-190 | REWRITE | Trigger, banner location and "in a row" are wrong for sends; the code is a Graph-wide OAuth code used by Instagram, Facebook and the Template Manager too, so the cross-channel part should be split from the WhatsApp reconnect part (keep the key: `DOC_ARTICLES` depends on it, `documentationLinks.js:48`) | E1-E9 |
| whatsapp-number-status | KEEP | UI facts, admin gating and the risky-status list are verified; needs a Meta-source pass and one internal inconsistency fixed ("Rate limited") | F1, F2, F2b |
| whatsapp-quality-and-limits | KEEP | Verified what Lynomia stores/logs; contains no invented numbers; Meta semantics unsourced | F1, F2, F2b |
| whatsapp-display-name | KEEP | Thin on repo facts (it only reports `name_status`) so almost every claim is Meta's and unsourced; short, so cheap to source | F3 |
| whatsapp-nothing-arrives | EXPAND | Strings verified, but one row contradicts the UI ("there but empty") and a real cause evidenced in the repo (stale phone-level callback override) is absent | F4-F6 |
| whatsapp-reconnect-a-number | KEEP | The five refusal strings are verbatim from `en.yml`; fix invented timings and the unqualified "release the number from Meta" | F7, E7 |
| whatsapp-number-already-connected | KEEP | Installation-wide uniqueness verified; one claim ("inboxes you may have archived") has no basis in the product | F8 |
| whatsapp-contact-info-requests | KEEP | The six reasons match `en.yml` exactly; paraphrased rather than quoted, and one limit is a duplicate | F9 |
| whatsapp-business-scoped-contacts | KEEP | Both refusals verified against the guard and `en.yml`; "certain entry points" is Meta's and unsourced | F10 |
| whatsapp-find-a-failed-message | KEEP | Filter label, "contains" semantics and the one-day retry limit verified; the content is channel-agnostic (IA question for 062, not a Phase 1 move) | F11 |

---

## 3. Accuracy against the product

Verdict vocabulary: `confirmed | wrong | unverifiable`. I add `partly` where the sentence is true on one path and
not another, and `unverifiable (Meta)` where the only possible evidence is Meta's.

### A. whatsapp-error-131049

| # | claim in the article | evidence | verdict |
|---|---|---|---|
| A1 | Retry is withdrawn for this code, with the reason stated | `delivery_failure.rb:29,54`; `messages_controller.rb:33-41`; `MessageError.vue:56-58,137-139`; server string `en.yml:186` | confirmed |
| A2 | "WhatsApp's own words begin with `131049`" | status-webhook path writes `"#{code}: #{title}"` (`incoming_message_base_service.rb:73-76`); request-time refusals store only Meta's `error.message`, no code (`whatsapp_cloud_service.rb:166-169`, `providers/base_service.rb:44-57`), and `CODE_IN_ERROR = /\A(\d{3,6}):/` (`delivery_failure.rb:35`) cannot match that | partly |
| A3 | Per-recipient, interleaved with delivered/read messages on the same number | recorded observation: `delivery_failure.rb:13-15`; `spec/services/whatsapp/delivery_failure_spec.rb:1-5`. The raw data is not in the repo | confirmed as a recorded observation; not re-checkable here |
| A4 | It is Meta's per-person cap on marketing messages | in-repo support is the observation above and the classification comment; no Meta URL appears anywhere in the repo, although `docs/p7/04-whatsapp-failure-ux.md` ("Copy") says the copy was grounded in Meta's documentation | unverifiable (Meta) |
| A5 | UTILITY is not capped the same way; Meta reads content and reclassifies; the cap "lifts by itself"; no support request clears it; each retry is "one more signal against your number's quality rating" | the last two are repeated as code comments (`delivery_failure.rb:5-7`, `messages_controller.rb:29-32`) and in a user string (`en.yml:186`) with no source | unverifiable (Meta) |
| A6 | What to do: "Nothing, for that message" | in-product copy says more: reply freely for 24 hours if the customer writes, "otherwise WhatsApp asks you to wait at least a day" (`en/chatlist.json:179`). The article never gives the wait | partly (omits the product's own advice) |
| A7 | "There is no list of restricted contacts anywhere in the product" | the code appears only in the classifier, its specs and the registry wiring | confirmed by absence |
| A8 | "A campaign reports the failure per message" | campaign delivery table has Contact, Status, **Reason**, **`Code {code}`** columns (`en/campaign.json:281-290`; `CampaignDeliveryTable.vue:38-47,135-147`). True, and the article does not say that is where the code is read | confirmed (incomplete) |
| A9 | Worked example: 4,000 contacts, 37 failures, a fortnight's gap | invented figures presented as an account | unverifiable (illustrative) |

### B. whatsapp-error-131042

| # | claim | evidence | verdict |
|---|---|---|---|
| B1 | Account-scoped; Retry kept because an admin can fix billing | `delivery_failure.rb:16-18,30,56-59`; `MessageError.vue:54-55`; `messages_controller.rb:36-40` (only recipient-scoped is refused); `messages_controller_spec.rb:325-326` | confirmed |
| B2 | "Retry stays available"; the worked example presses Retry after fixing billing | the button exists only while the message is under one day old: `!hasOneDayPassed(createdAt)` (`MessageError.vue:60-66`; `shared/helpers/timeHelper.js:156-159`). A billing fix that takes two days leaves no Retry. The 131042 article never says so; `whatsapp-find-a-failed-message` does (EN line 72) | wrong by omission |
| B3 | "Nothing here retries a WhatsApp message on its own" | `delivery_failure.rb:48-50`; a refusal is saved and the job returns (`providers/base_service.rb:44-57`); `SendReplyJob` has no `retry_on` (`app/jobs/send_reply_job.rb`) | confirmed |
| B4 | Causes: no payment method, declined card, currency mismatch | the classifier comment says only "currency or payment method is not usable" (`delivery_failure.rb:16-17`); the captured Meta title is "Business eligibility payment issue" (`spec/jobs/webhooks/whatsapp_events_job_live_status_spec.rb:66-70`). "Declined card", "most often" have no source | partly; remainder unverifiable (Meta) |
| B5 | "Account Health does not report billing" | `PERSISTED_FIELDS` has no billing field (`health_service.rb:20-38`) | confirmed |
| B6 | "This is the one in this section that is genuinely yours to fix" (AR: "the only") | contradicted in-section: an admin reconnecting for 190, changing a display name, fixing audiences, registering a webhook are all fixable by the reader | wrong |
| B7 | Observed in production | a verbatim status payload captured from a live server's journal: `whatsapp_events_job_live_status_spec.rb:3-9` | confirmed |

### C. whatsapp-error-131053

| # | claim | evidence | verdict |
|---|---|---|---|
| C1 | Lynomia uploads first and sends by media id | `whatsapp_cloud_service.rb:191-192`; `media_upload_service.rb:1-5,12-20` | confirmed |
| C2 | If you see it, "the send fell back to something Meta had to fetch" | fallback is `{ 'link' => attachment.download_url }` whenever the upload returns nil (`whatsapp_cloud_service.rb:192`); upload returns nil on any failure (`media_upload_service.rb:17-27`) | confirmed |
| C3 | "An upload has a long but finite timeout" | 60 s open, 300 s read (`media_upload_service.rb:8-9`) | confirmed |
| C4 | "`131053` means WhatsApp tried to download a file from your installation and could not" | the only source is a code comment ("rate limited per destination ASN and returns intermittent 131053 errors", `media_upload_service.rb:4-5`; `whatsapp_cloud_service.rb:191`) that came in with upstream Chatwoot (#15702, `docs/chatwoot-upgrade/appendix/A-upstream-whatsapp-analysis.md:338`). It is not a Meta page and not a Lynomia observation. Whether Meta's own title for 131053 says this is unchecked | unverifiable (Meta) |
| C5 | (omitted) the operator switch `WHATSAPP_MEDIA_UPLOAD_STRATEGY=link` restores link sending and therefore re-creates the failure | `media_upload_service.rb:31-34`; documented as an upgrade ops note `docs/chatwoot-upgrade/01-upstream-diff.md:43` | gap |
| C6 | "Press Retry … Retry is offered" | true by default (unclassified code takes the default branch, `MessageError.vue:60-66`), subject to the one-day limit; and the failure UI shows **no** Learn-more link for it, because unclassified | confirmed (with B2's caveat) |

### D. whatsapp-error-131060

| # | claim | evidence | verdict |
|---|---|---|---|
| D1 | The placeholder is kept on purpose rather than dropping the event | `incoming_message_base_service.rb:92-102` | confirmed |
| D2 | "The conversation shows an incoming message with no content" | stored content is "This message is unavailable." (`config/locales/en.yml:455`), but the agent sees the Unsupported bubble: "This message is unsupported. You can view this message on the WhatsApp app." (`bubbles/Unsupported.vue:22-23`; `en/conversation.json:79`) | wrong |
| D3 | It happens with "some interactive and system message types, and media WhatsApp itself could not process" | the only repository statement ties 131060 to **coexistence companion-device syncs** (`incoming_message_base_service.rb:92-94`; `docs/real-whatsapp-uat/07-coexistence.md:93`; `docs/whatsapp-qr/07-meta-coexistence-pivot.md:259`). The article never mentions coexistence | unverifiable (Meta); the evidenced cause is omitted |
| D4 | "The code behind that is 131060" | no code reads 131060. The branch keys on `type: unsupported` (`incoming_message_base_service.rb:84,95`); the log line records the error *title* and sender only (`incoming_message_service_helpers.rb:79-81`). A user never sees "131060" in the product | wrong as a user-facing premise |
| D5 | "It is not reported as a failure anywhere" | a `Rails.logger.warn` line exists (`incoming_message_service_helpers.rb:79-81`); no operator-log event or Sentry capture | confirmed (a log line only) |
| D6 | The 24-hour window opens from the customer's message | `message_window_service.rb:2,27-28,34-37` | confirmed |
| D7 | Worked example (a forwarded catalogue product) | invented | unverifiable (illustrative) |
| D8 | (not in article) a message event carrying `errors[]` that is not typed `unsupported` is logged and the method returns | `incoming_message_base_service.rb:85` (`log_error(message) && return if error_webhook_event?`); depends on `Logger#warn` returning truthy — not run | unverified; the "customer says they wrote and nothing is there" cause this could explain is undocumented |

### E. whatsapp-error-190

| # | claim | evidence | verdict |
|---|---|---|---|
| E1 | "Two authorization refusals in a row and the inbox is marked" (worked example: "after the second refused send the banner appears") | The threshold is 2 and `Channel::Whatsapp` does not override it (`reauthorizable.rb:16,34`; overrides exist only for email, tiktok, instagram: `channel/email.rb:42`, `tiktok.rb:30`, `instagram.rb:25`). But for WhatsApp the **only** caller of `authorization_error!` is the inbound **media-download 401**, and only when Meta attributes it to OAuth (`incoming_message_whatsapp_cloud_service.rb:22,41-56`). The outbound send path never calls it (`providers/base_service.rb:44-57`; repo-wide grep of `authorization_error!` finds no send-path caller for WhatsApp). The counter is cumulative, not consecutive: it resets only in `reauthorized!` (`reauthorizable.rb:68-75`). Recorded as SHO-64, `docs/p7/00-discovery-findings.md:833`, still true at baseline | wrong |
| E2 | A banner appears "at the top of the dashboard" | the banner is `InboxReconnectionRequired` rendered **inside the inbox's settings page** (`routes/dashboard/settings/inbox/Settings.vue:832`), for WhatsApp only when `source === 'embedded_signup'` (`Settings.vue:410-415`). A manually-connected number gets no banner. The dashboard-wide signal is a ruby alert icon beside the inbox in the sidebar (`ChannelLeaf.vue:30-32,63-69`). Banner text: "Your inbox is disconnected. You won't receive new messages until you reauthorize it." (`en/inboxMgmt.json:9`) | wrong |
| E3 | The article treats Account Health's "needs to be refreshed / needs attention" and the latch as one signal | they are two: Account Health shows those titles when the health fetch itself fails with code 190 (`inbox_health_management.rb:36-42`; `health_service.rb:12-14`; `en/inboxMgmt.json:937-945`), and that path does **not** latch. A latch also happens immediately, without the threshold, on webhook-setup failure (`channel/whatsapp.rb:169-176`) and on a failed embedded signup (`embedded_signup_service.rb:79`) — neither is in the article | wrong (conflated), incomplete |
| E4 | "The account's administrators are emailed" | `reauthorizable.rb:93`; `channel_notifications_mailer.rb:17-19`; sent only when SMTP is configured or in development, to `Current.account.administrators` (`administrator_notifications/base_mailer.rb:3-9,25`) | confirmed (conditional) |
| E5 | "Incoming messages are still accepted and stored" | `whatsapp_events_job.rb:147-158`: a latched channel ingests and "loses at most its attachments". The article omits the attachment loss | confirmed (incomplete) |
| E6 | Admin-only; remedy differs for embedded vs manual | `inbox_policy.rb:79-81`; Account Health descriptions "reconfigure it using Embedded Signup" / "verify or replace it" (`en/inboxMgmt.json:940,942`) | confirmed |
| E7 | "Deleting and recreating the inbox … can release the number from your Meta app" (repeated in number-status, reconnect, already-connected, whatsapp-troubleshooting) | `before_destroy :teardown_webhooks` (`channel/whatsapp.rb:48`) deregisters the phone number and may unsubscribe the app **for embedded-signup channels only**; manual numbers are deliberately left alone (`webhook_teardown_service.rb:41-50,55-65`) | confirmed for embedded signup; overstated for manual |
| E8 | Why a token dies (expired, revoked, permission removed, app changed); "a token you generated by hand will expire again" | Meta token lifetimes. A system-user token need not expire; the sentence generalises. Route to 001/002 | unverifiable (Meta) |
| E9 | Written and titled as a WhatsApp code | the same OAuth code 190 latches Instagram (`instagram/base_send_service.rb:76`, `instagram/message_text.rb:44`, `builders/messages/instagram/message_builder.rb:27`; threshold **1**, `channel/instagram.rb:25`), Facebook (`builders/messages/facebook/message_builder.rb:31,152`; string-matched at `facebook/send_on_facebook_service.rb:114-118`), the Template Manager (`custom/app/services/whatsapp/templates/operation.rb:11,54` → `AUTH_INVALID`) and the Account Health fetch. No subcode handling anywhere | incomplete by scope |

### F. symptom articles

| # | article | claim | evidence | verdict |
|---|---|---|---|---|
| F1 | number-status, quality | six statuses are "risky"; yellow/red rating are "risky"; a transition writes an operator-log line | `health_service.rb:39-40`; `log_risky_transition` `health_service.rb:213-223` (`[WHATSAPP HEALTH] risky_phone_number`) | confirmed |
| F2 | number-status, quality | Account Health admin-only; custom roles have no inbox permission; no history kept | `inbox_policy.rb:79-81`; `custom/app/models/custom_role.rb:19-27`; single stored record `health_service.rb:20-38` | confirmed |
| F2b | number-status, quality | what each status/rating/tier *means* (Flagged keeps sending, Banned appealed in WhatsApp Manager, tier = unique customers per rolling 24 h, tiers rise "on their own") | nothing in the repo states these. Also internally inconsistent: number-status says Rate limited = "too many messages too quickly" (EN line 17); quality says hitting the unique-customer ceiling "shows up as Rate limited" (EN lines 32-34) | unverifiable (Meta) |
| F3 | display-name | name state is reported; refusal reasons; "messages keep sending"; "customer sees your number" | `name_status` stored (`health_service.rb:24`); the rest is Meta's | partly; remainder unverifiable (Meta) |
| F4 | nothing-arrives | table strings "Webhook not configured", "Register Webhook", "Health data is not available", "WhatsApp connection needs to be refreshed" | `en/inboxMgmt.json:913,1087-1088,844,936,939` | confirmed |
| F5 | nothing-arrives | "An incoming message that is there but empty" | wrong for the same reason as D2 | wrong |
| F6 | nothing-arrives | "Webhook not configured … the commonest cause by a wide margin"; "messages sent while the webhook was missing are gone, no replay" | no frequency data in the repo; replay is Meta's retry behaviour (026). The repo itself records a different real cause — a **stale phone-level callback override** pointing a number at a host that answered 502 (`spec/jobs/webhooks/whatsapp_events_job_live_status_spec.rb:7-10`) — absent from the article. "No backfill in the product" is consistent with `docs/whatsapp-qr/07-meta-coexistence-pivot.md:259` ("History import … Not implemented") | unverifiable (Meta) |
| F7 | reconnect | five refusal strings | verbatim in `config/locales/en.yml:181-184,198`; Configuration tab `Settings.vue:232`, Account Health tab `:253`. "Total time, about four minutes" and "five-minute reconnection" are invented | confirmed; timings unverifiable |
| F8 | already-connected | one number, once per installation; "including inboxes you may have archived" | uniqueness `channel/whatsapp.rb:40`, `channel_creation_service.rb:14`; the actual string is "Channel already exists for this phone number: %{phone_number}, please contact support if the error persists" (`en.yml:184`) — worth quoting. No archived-inbox state exists in `app/models/inbox.rb` or `en/inboxMgmt.json` | confirmed; "archived" wrong |
| F9 | contact-info-requests | six reasons; "a failed request does not count as pending" | `en.yml:190-195`; evaluation order `contact_info_request_eligibility_service.rb:60-71`; `where.not(status: :failed)` at `:124`. Paraphrased, not quoted. Last Limit bullet ("A shared number cannot be requested twice in parallel") restates the pending rule | confirmed |
| F10 | business-scoped | the two refusals; "Sync templates" | `authentication_template_guard.rb:6-9`; `en.yml:187-188`; `en/whatsappTemplateMgmt.json:7`. "WhatsApp does this when the customer reaches you through certain entry points" is Meta's | confirmed; remainder unverifiable (Meta) |
| F11 | find-a-failed-message | Filter "Message delivery → Failed to send"; matches a conversation that *contains* such a message; one-day retry limit; operator diagnostic exists | `en/advancedFilters.json:71,77`; `conversations/filter_service.rb:60-66,84`; `MessageError.vue:65`; `lib/tasks/whatsapp_diagnose.rake:1-25` prints recent failures verbatim (`diagnosis/inbound_evidence.rb:73-83`) | confirmed |

Not checked: the AR dashboard's runtime fallback when a locale key is missing (`entrypoints/dashboard.js:37-41`
sets `locale: 'en'` and no `fallbackLocale`); I report only what the AR locale files contain.

---

## 4. Missing articles

The rule I applied: an article is missing only if the repository shows a user can *reach that state* and there is no
page for it. I list no Meta code that Lynomia has never displayed or special-cased — which Meta codes earn pages is
for the Meta agents (005, 025, 028) working from the source register, not for this report.

| missing page | the user question it answers | repository evidence that the state is reachable |
|---|---|---|
| **A code with no page** — what to read and what to send support | "My message failed with a number that is not listed. What do I do?" | the hub says there is nothing for such a code and stops (`whatsapp-troubleshooting.md:101-105`); that path is the default for every unclassified code (`delivery_failure.rb:9-11,50`); the operator log already tags it `classification=UNCLASSIFIED` (`custom/app/services/custom/messages/status_update_service.rb:28-44`); Retry is on by default and ends at one day (`MessageError.vue:60-66`) |
| **A failure with no code at all** — Meta's sentence vs a Lynomia refusal | "It says 'Template not found or invalid template name' / 'window is closed'. Is that Meta or Lynomia?" | two strings are Lynomia's own (`en.yml:185`; `send_on_whatsapp_service.rb:40`), request-time Meta refusals are stored as bare text without a code (`providers/base_service.rb:44-57`); the diagnostic itself calls the distinction essential (`diagnosis/inbound_evidence.rb:124-126`) |
| **Token no longer valid, across channels** (the Graph 190 family) | "My Instagram / Messenger / WhatsApp inbox says reconnect. Why, and how?" | one code, four channels, different thresholds and remedies (E9). No Instagram or Messenger page exists anywhere in the corpus (`troubleshooting/` holds only commerce and support) |
| **Account Health error with a code and subcode** | "Account Health says Meta could not return health details and shows an error — what now?" | the endpoint returns `code`, `subcode`, `http_status` (`inbox_health_management.rb:36-42`) and the UI says "Review the error below" (`en/inboxMgmt.json:944-945`); `nothing-arrives` has one table row for it |
| **Reading a campaign's Reason and Code columns** | "My campaign shows Failed, Code N, Reason … — which of these can I fix?" | `en/campaign.json:281-290`; 052 owns the campaigns section, so this may belong there with a link back |
| **Template Manager refusals** | "Lynomia would not submit / sync my template: NAME_TAKEN, AUTH_INVALID, RATE_LIMITED, META_UNAVAILABLE" | a second Meta-error vocabulary with its own codes (`custom/app/services/whatsapp/templates/error.rb:6-9`; mapping `operation.rb:50-57`, including code 100 with subcode 2,388,024 → NAME_TAKEN, `operation.rb:9-10,53`). 053 owns `whatsapp-template-lifecycle` |
| **131060 as coexistence** (a rewrite target, not a new page) | "My customer's message shows 'unsupported — view it on the WhatsApp app'. Did we lose it?" | D3 |
| **A section index** | "I have a number. Which page is it?" | today a hand-written paragraph in another section's article (`whatsapp-troubleshooting.md:101-122`); fine at 14 pages, a maintenance failure at 100 |

Other numeric Meta codes the **executable** code already special-cases and no article mentions: 1609005 (Instagram
story link cannot be scraped → attachment dropped, text replaced, `builders/messages/instagram/message_builder.rb:30-34`)
and subcode 2018218 under code 100 (Facebook profile lookup, deliberately swallowed,
`builders/messages/facebook/message_builder.rb:156-158`). Codes 131030, 100 and subcode 2655007 appear only as
illustrations in a comment (`whatsapp/provider_error_log.rb:47`) and carry no behaviour.

---

## 5. Quality

**Structure (28 files, measured).** Every article opens with a lede paragraph (no H1; title is front matter), then
topic H2s, then the same three closing H2s: **Who can do this**, **Limits**, **Related** (14 of 14 EN, 14 of 14 AR).
**A worked example** appears in 7 of 14 (131049, 131042, 131060, 190, nothing-arrives, quality-and-limits, reconnect).
`description` begins "You will know …" in 14 of 14 (AR: "ستعرف …"). EN and AR have the same number of H2s in every
article. The uniformity is a strength: it makes the "Limits" list a reliable place to look for what the product cannot do.
(I read only this section closely; I make no comparison with other sections.)

**Task orientation.** Good. The best sentences are the product-behaviour explanations that stop an agent reading a
deliberate behaviour as a bug (why Retry is withdrawn for 131049 and kept for 131042; why a placeholder exists; why
media is uploaded first). The symptom articles that quote exact product strings (`reconnect`, `contact-info-requests`,
`business-scoped-contacts`) are the strongest at being found by someone searching the text they are looking at.

**Weaknesses, all measured:**

- No article quotes **Meta's verbatim title** for its code, though two are in the repo
  ("This message was not delivered to maintain healthy ecosystem engagement." — `delivery_failure_spec.rb:26`;
  "Business eligibility payment issue" — `whatsapp_events_job_live_status_spec.rb:70`). A reader who pastes the string
  they see ("WhatsApp said: 131049: This message …") finds the article only through the number.
- No article states a **Meta source, API version or date checked**. All Meta behaviour is therefore unauditable
  by a reader and by agent 088.
- Four EN H1 titles exceed 60 characters (business-scoped 66, 131049 63, 131060 62, 131042 61). Every `seo_title`
  is ≤ 60 (maximum 60: quality-and-limits) and every `seo_description` is 50-160 (EN 109-154, AR 84-128), so no audit
  warning is expected from front matter; I did not run the audit.
- **Zero screenshots** in 28 files. The articles rely on exact navigation strings instead, which is only safe if the
  strings are right (§6 shows the Arabic ones are not always).
- **Invented specifics** presented as events: "4,000 contacts / 37 failures / a fortnight", "about four minutes",
  "five-minute reconnection", "a catalogue product". They read as evidence and are not.
- **Tags** are `[whatsapp, errors, <topic>]` ×14; no tag carries the code, so portal search/tag views cannot
  group by code. The `errors` tag repeats the category.
- **Position** orders the five codes by salience (131049, 131042, 131053, 131060, 190), not numerically; at 50+
  codes that stops being scannable.
- The seeder **drops unknown front-matter keys**: `meta_for` copies only `doc_key, title, description, tags,
  version, release_date` (`content_seeder.rb:106-113`). So code, scope or source cannot be stored on the article today.

**What guards the section mechanically** (`content_seeder_corpus_spec.rb`): EN/AR key parity, every `](key)` link
resolves, `title` and integer `position` present, same section and position per locale, every `DOC_ARTICLES` slug exists,
and an article exists for every key in `DeliveryFailure::CODES` (`:81-83`). **Not guarded:** that a UI string quoted
in an article exists in that language's locale file, that a code article has the required sections, that an article
exists only for a code with a record, that two locales have the same headings.

---

## 6. EN/AR parity

**Structure: perfect.** Same 14 keys, same position, tags, link set, table row counts and H2 count in every pair;
the AR is a close translation, line for line (worked-example figures, weekdays and durations all agree). In the line-by-line
pass I made, no AR article adds a claim the EN one lacks.

**Meaning: one kind of mismatch, six instances — the AR article names a UI label that the AR product does not
show.** The AR articles translate English UI labels independently of `app/javascript/dashboard/i18n/locale/ar/*.json`.

| AR article says | AR locale file says | where |
|---|---|---|
| "فشل الإرسال" for the failed-message marker (131049 line 9; find-a-failed-message lines 9, 30) | `"FAILED_TO_SEND": "تعذّر الإرسال"` | `ar/chatlist.json:28` |
| tab "**التهيئة**" for Configuration (190, reconnect) | `"CONFIGURATION": "الإعدادات"` — the same word as the Settings tab | `ar/inboxMgmt.json:779-781` |
| tab "**سلامة الحساب**" for Account Health (8 articles) | the literal English `"Account Health"` | `ar/inboxMgmt.json:787` |
| button "**تسجيل Webhook**" | the literal English `"Register Webhook"` | `ar/inboxMgmt.json:991` |
| filter path "تسليم الرسائل ← يساوي ← فشل الإرسال" | `MESSAGE_STATUS` keys **absent** from `ar/advancedFilters.json` (125 lines; EN has 132 with the keys at `en/advancedFilters.json:71,77`) | what the Arabic UI shows for this filter is unverified (no `fallbackLocale`, `entrypoints/dashboard.js:37-41`) |
| (190, nothing-arrives) banner / Account Health error text | English strings in the AR file: `ar/inboxMgmt.json:9,839-844` | an Arabic reader sees English where the article gives Arabic |

Either the AR locale is incomplete (a Crowdin matter) or the articles are ahead of it. Either way a stuck Arabic
reader sees words the article does not use, and no check catches it. Settings → Inboxes itself matches
(`ar/settings.json:353`, `ar/inboxMgmt.json:3`). For 061/094.

**Smaller mismatches.**

- 131042 AR says the error is "الوحيد" (**the only**) in the section whose fix is yours; EN says "the one". AR
  strengthens a claim already wrong in EN (B6).
- 131053 AR table row 3 drops "filtered to failed messages" (EN line 35 → AR line 33).
- 131049 AR uses "حجبت" for *withheld* (line 9), "محجوب" for *banned* in the next paragraph (line 12) and in the
  status table of number-status, and "بحجب الرقم" for *recipients blocking the number* (quality-and-limits line 14):
  one root, three meanings. Not an error in any one sentence; a hazard for a reader skimming.
- The contact-info Limit "لا يُطلب رقم مشترك مرتين" is as unclear as the EN "A shared number cannot be requested twice".

---

## 7. Coverage versus classification — exact

`Whatsapp::DeliveryFailure::CODES` has **two** entries: `131_049` (scope recipient) and `131_042` (scope account)
(`custom/app/services/whatsapp/delivery_failure.rb:28-31`). Its own header says only codes "actually observed on its
own traffic" are classified (`:9-11`).

| code | article | classified | executable handling in the repo | reaches the failed-message UI | provenance of "seen here" |
|---|---|---|---|---|---|
| 131049 | `whatsapp-error-131049` | **yes** (recipient) | classification, retry refusal (`messages_controller.rb:36-40`), UI explanation (`MessageError.vue:31-39`) | **yes**, Learn more → article (`:70-77`) | observed on live traffic (`delivery_failure_spec.rb:1-5`; P7-B) |
| 131042 | `whatsapp-error-131042` | **yes** (account) | classification only | **yes** | captured live payload (`whatsapp_events_job_live_status_spec.rb:3-9`) |
| 131053 | `whatsapp-error-131053` | no | none — comments only (`whatsapp_cloud_service.rb:191`; `media_upload_service.rb:5`) | no (null `deliveryFailure` → no link, `MessageError.vue:70-72`) | upstream Chatwoot change (#15702); no Lynomia observation |
| 131060 | `whatsapp-error-131060` | no | none — comment only (`incoming_message_base_service.rb:93`); behaviour keys on `type: unsupported` | no; and it is an *incoming* event, never a failed outgoing message, and no UI shows the number | comment plus coexistence design docs; no observation |
| 190 | `whatsapp-error-190` | no | yes, many sites, none of them `DeliveryFailure`: `health_service.rb:12-14`; `incoming_message_whatsapp_cloud_service.rb:50-56`; Template Manager `operation.rb:11,54`; Instagram ×3; `social_channels/provider_name_backfill_service.rb:157` | no | generic `Reauthorizable`; the "real UAT" saw 190 only from a fixture token (`docs/real-whatsapp-uat/10-real-uat-results.md:10`) |

Consequences:

- **The statement "the five codes this installation classifies" (`01-current-system.md` §7, charter §1.2,
  `documentationLinks.js:41-43`) is wrong on both counts.** Two are classified. Only those two have a production
  observation record in the repo. The other three were written from upstream code comments and generic code. The
  hub's sentence "those are the ones this installation has actually seen" (`whatsapp-troubleshooting.md:103-105`) is
  true of two. `docs/p7/09-whatsapp-error-knowledge-base.md:28-34` is honest about the evidence ("a line the repo can
  point at") but its 190 row cites `ApiError#authorization_error?` and the threshold, neither of which is the send path.
- **Classification gates the link.** `push_event_data` returns nil for an unclassified code
  (`delivery_failure.rb:64-68`), so `MessageError.vue` never learns the code, so `whatsappErrorArticle()` is only ever
  called with 131049 or 131042. The `?? 'whatsappTroubleshooting'` fallback (`MessageError.vue:73-76`) is unreachable
  today. **Adding Meta error articles to the corpus does not put them in front of a user** unless either
  `CODES` grows (each new *classification* also needing title/body strings in both `chatlist.json` files, `en:172-185`) or the
  UI resolves a raw code.
- **Three `external_error` formats exist for Meta channels**, and the classifier parses one:
  WhatsApp status webhook `"<code>: <title>"` (`incoming_message_base_service.rb:73-76`); WhatsApp request-time
  Meta `error.message` only, no code (`whatsapp_cloud_service.rb:166-169`); Facebook and Instagram
  `"<code> - <message>"` (`facebook/send_on_facebook_service.rb:73-79`; `instagram/base_send_service.rb:69-79`). Twilio
  uses `"<code> - <message>"` and Telegram `"<code>, <description>"`. `CODE_IN_ERROR` is `/\A(\d{3,6}):/`
  (`delivery_failure.rb:35`). A Messenger/Instagram error article cannot be linked by the current parser even if its
  code is added.
- **Whether Meta ever returns 131049/131042/131053 synchronously** (which would store them without a code and defeat
  classification) is unverified here. Route to 005/007.

---

## 8. The pattern — what this section does, and what separates strong from weak

Three kinds of article share one section: **code articles** (5), **refusal-state articles** where the user sees a
specific Lynomia/Meta message (number-status, display-name, number-already-connected, contact-info-requests,
business-scoped-contacts), and **procedure/concept articles** (nothing-arrives, reconnect, quality-and-limits,
find-a-failed-message). Every article, whatever its kind, makes three classes of sentence, and the section never
separates them:

- **L** — Lynomia behaviour (what the product does, shows, gates). Verifiable in code.
- **O** — an observation of Meta's behaviour on this installation (recorded fixture, journal, investigation).
- **M** — Meta behaviour or policy (caps, categories, token lifetimes, appeal routes, retry behaviour). Verifiable only
  at a Meta page.

| article | L | O | M | what the weak ones did |
|---|---|---|---|---|
| 131049 | strong | yes | unsourced | — |
| 131042 | strong (minus the one-day limit) | yes | unsourced | — |
| 131053 | strong | **none** | definition from a comment | defined the code from a comment; omitted the env switch |
| 131060 | partly wrong (UI) | **none** | invented types | described UI from imagination; ignored the one evidenced cause |
| 190 | **wrong** (trigger, banner) | **none** | unsourced | described intended design, not shipped behaviour |
| symptom articles | strong (strings verbatim, policies cited) | n/a | unsourced in at least 5 of 9 (number-status, quality-and-limits, display-name, nothing-arrives, business-scoped-contacts) | — |

**What the two strong code articles do that the weak three do not:**

1. They start from an **incident with a record**, so the sentence "this is what happened" has an artifact behind it.
2. They explain a **Lynomia decision the reader will mistake for a bug**, and that decision exists as code at a
   cited line (the Retry asymmetry).
3. They separate **Meta's rule from Lynomia's policy** ("the cap is Meta's; withdrawing Retry is ours").
4. They name **where the fix lives and who can do it** (business.facebook.com; an administrator of the Business
   account, who may not be a Lynomia admin).
5. Their central claims are **pinned by tests**, not only by comments (`delivery_failure_spec.rb`; `messages_controller_spec.rb:291-330`;
   `message/specs/MessageError.spec.js`).

The weak three invert each: no incident, a code comment taken as the definition, UI described from memory.

**Why the symptom articles are the better half of the section:** they are anchored to *strings the product emits*
(`en.yml`, `inboxMgmt.json`) and to *policies in code* (`InboxPolicy#health?`, `RISKY_STATUSES`), both checkable.
They are the pattern to scale — and the reason is not that they avoid Meta, but that their central facts are
verifiable from the repository.

**The P7 rule and where it over-reached.** P7-F wrote "the set is the failure modes this repository can point at a
line for" (`docs/p7/09-whatsapp-error-knowledge-base.md:18-19`). That is the right rule for **L** claims and it was
not fully applied (190, 131060). As a rule for *which Meta codes get a page* it was a proxy for "we have no source".
The program now has a Meta source register (`03-meta-source-register.md`); with a normative source, a code Lynomia can
*display* and that has a distinct remedy can earn a page without having been observed here — provided every **M**
sentence cites its source row and no **L** sentence is written from design intent.

---

## 9. Proposed canonical error-article shape

Principle: **an error article answers, in this order, "what am I looking at, whose problem is it, can I retry, what do
I do" — and every sentence belongs to exactly one evidence class (L, O, M) that a reviewer can check.**

### 9.1 Kinds

| kind | when | example in this section |
|---|---|---|
| **code** | Lynomia classifies or special-cases the code, **or** a distinct, sourced remedy exists for a code the product can display | 131049, 131042 |
| **family** | several codes share one remedy (follows `commerceErrorArticle`'s "grouped by remedy", `documentationLinks.js:139-150`); the codes are a table, each with Meta's verbatim title | not yet present; 190 should become one |
| **symptom** | the user has a string or state, no code | the nine |

One article per code only where Lynomia's behaviour *differs* per code. Otherwise a family, with every member code
resolving to it. Keep the existing key form `<product>-error-<code>`: it is the contract the registry already uses and
the string a person pastes into a search engine (`docs/p7/09-whatsapp-error-knowledge-base.md:93-94`); a family takes a
remedy-named key and its codes resolve to it.

### 9.2 Skeleton

```
---
title:        "<Product> error <code> — <plain-language meaning>"   # code first, ≤ 60 chars where possible
description:  "You will know …"                                       # keep: 14/14 today, outcome-stated
position:     <int>
tags:         [<product>, errors, <surface>]
seo_title / seo_description                                           # as today
# proposed (needs a seeder change; content_seeder.rb:106-113 currently drops them):
codes:        [131049]            # code(s) and optional subcode(s) this page answers; drives the resolver
scope:        recipient|account|token|content|transient|local
retry:        never|after-fix|maybe
sources:      [<Meta URL>, …]     # the M sentences' source rows
checked:      2026-10-13          # date Meta sources were last read
---
<lede: what you see, in the product's own words, and what it is NOT — 2-3 sentences>

## At a glance
| Whose problem | recipient / your account / your token / Lynomia / Meta |
| Retry         | offered / withdrawn (why) / available for one day after you fix it |
| Who can fix   | any agent / administrator / Business Manager admin / nobody |
| Where you see it | the message bubble ("WhatsApp said: …") / campaign table Code column / Account Health / banner / nowhere |

## What it means
<Meta's verbatim title in a quote, then the plain meaning. Only M sentences, each traceable to `sources`.>

## Why Lynomia behaves this way        # only if the product does something non-obvious
## What to do                          # numbered; UI labels quoted exactly from that locale's file
## If it is not this                   # the look-alikes (Restricted vs 131042; 190 vs webhook not configured)
## Who can do this
## Limits                              # negative claims; each checked by absence in code
## Related
```

### 9.3 Reasons

1. **Lede + "At a glance" first.** The two strong articles each spend a whole section on retry/scope/who because that
   is what agents misread. Put it in a fixed place so the answer is the same shape every time and a machine can read it.
2. **Meta's verbatim title.** The user pastes what the product shows (`WhatsApp said:` label,
   `en/chatlist.json:173`); the page should contain that string, and the audit trail starts there.
3. **"What it means" is the only place M sentences live, with `sources`/`checked`.** Today M and L are interleaved with
   no provenance; agent 088 cannot refute what has no source. Separating them is what lets a reviewer check each class
   with the right tool (grep for L, a Meta page for M).
4. **Exact UI strings quoted from the locale file of that language**, not translated from English. This is the
   cheapest fix for §6, and it is checkable.
5. **"If it is not this."** The section's most useful single sentence is a disambiguation
   (`number-status` line 38-39: *Restricted* and 131042 "have nothing to do with each other"); make it a heading so
   it is never omitted.
6. **Worked example optional, never invented numbers.** If used, label it illustrative; never use it to carry a
   mechanism the code does not implement (the 190 example does).
7. **Keep "Who can do this", "Limits", "Related".** They are 14/14 and they work.
8. **Structured front matter, extending `meta`, not a new table.** `codes` lets one resolver serve `/docs/...` and the
   dashboard; it can replace five hand-maintained JS keys and a hand-written hub paragraph, and some such mechanism is needed for the
   registry to scale. This is charter decision §8.4's input: the existing `meta` jsonb is enough; the seeder's
   `meta_for` is the single extension point.

### 9.4 Mechanical gates this shape makes possible (all extensions of the existing corpus spec)

1. Every error article has the required H2 set and the same H2 count in both locales.
2. Every quoted UI string exists in that locale's file (would have caught every row in §6).
3. Every `codes` entry resolves to exactly one article; every article with `scope` ≠ `local` has a non-empty `sources`.
4. A code-kind article requires either a `CODES` entry, an observation record, or a `sources` row — stated, not guessed.
5. A family article lists each code with Meta's verbatim title.

---

## 10. For the orchestrator to arbitrate

1. **Correct the baseline.** `01-current-system.md` §7 and charter §1.2: two codes are classified, not five; only
   two have a production record. (§7)
2. **190: fix the product or the article — decide before any rewrite.** The article documents behaviour that
   SHO-64 says does not exist (`docs/p7/00-discovery-findings.md:833`). Owners: 039/040 (product), 001/002 (token
   facts), 092 (claims vs code).
3. **Does corpus growth have to reach the UI?** If yes, the classification gate (§7) must change: widen `CODES`, or
   resolve raw codes in the UI, and handle the three `external_error` formats. Owners: 040, 041, 042.
4. **Keep or relax the "seen here" rule.** My recommendation is §8's last paragraph.
5. **Arabic UI labels.** Articles must quote the AR locale as shipped, or the locale must catch up (Crowdin). Owners:
   061, 094.
6. **Section IA.** Three kinds in one section (§8). `whatsapp-find-a-failed-message` and `quality-and-limits` are
   candidates to live elsewhere; any move must keep their keys, because `DOC_ARTICLES` names them
   (`documentationLinks.js:49-57`). Owner: 062, with 000.
7. **Meta claims to refute or source**, by agent: 017 (131049 cap, UTILITY, "lifts by itself", wait), 010/009
   (reclassification), 014 (display name, status meanings), 018 (tier, rate limited), 019/020 (131053 definition),
   026 (webhook retry/replay), 001/002 (token lifetimes), 015 (131060 / coexistence companion-device sync), 088
   (all of the above).
