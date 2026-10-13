---
agent: 060
scope: troubleshooting section of the corpus (7 articles x EN+AR, including the Platform Support Desk article contact-lynomia-support) classified, checked against code, analysed for article shape, with a proposed canonical troubleshooting-article pattern
confidence: high
---

# 060 — Corpus: `troubleshooting`

Read-only. All 14 files were read in full. Every checkable claim was traced to code and carries `path:line`. Every
string an article presents as "what you see" was tested with `rg -F` against the shipped locale files
(`app/javascript/dashboard/i18n/locale/{en,ar}/*.json`, `config/locales/{en,ar}.yml`). Nothing was run, rendered or
opened in a browser: where I say a page behaves a certain way (for example Arabic link targets) it is from reading
the route and controller. Claims that are about a provider (WooCommerce, Salla, Zid, Shopify, Meta) rather than
about Lynomia are marked `unverifiable` and routed, not resolved.

The headline, before the template sections:

1. **The five commerce articles open with a table of "what you see" strings, and none of the 19 strings exist in
   the product** (0 of 19 in `en/commerce.json`; the Arabic equivalents are translations of the invented English,
   not the Arabic locale). This is ledger item DC-14 (agent 056); I confirm it for every string and extend it in
   §3.2. The section's one promise — match what is on your screen to a cause — fails at its first step.
2. **Several articles state provider state Lynomia never received.** The sharpest: `NOT_APPLIED` is explained as
   "the store accepted the request", but the code can only produce that code after Lynomia *lost* the answer
   (`action_executor.rb:120`). The reconnect article names causes (key deleted, app uninstalled) that Lynomia
   inferred from a bare 401 or a refused or lost token refresh, and the uninstall it names actually takes a
   different path (`disconnected`, not `needs_reauth`). §3.4.
3. **Remedies are wrong or unreachable.** "Reconnect" is given for all four platforms (DC-15) but WooCommerce shows
   "Replace keys" and Salla shows no button. The Shopify and Zid scope remedies describe order actions that are
   held out of production (`switches.rb:16,21-26`). The address article's own four examples each produce a
   *different* message from the one it explains, it excludes Shopify (which also raises `INVALID_STORE_URL`) and
   tells Shopify merchants the opposite of what works.
4. **The best epistemic writing in the section is real and rare**: the "We do not know" section of the order-action
   article, and the support article's faithfulness to shipped UI strings. Nothing in the section tells the reader
   what Lynomia *recorded* versus what it *inferred*, and none of the five commerce articles has an escalation
   path (zero links to the ticket article; the hub does not link it either).
5. **The support article has four defects of its own** (§3.3, S1, S3, S9, S10): "two desks" above a three-row
   table; "a ticket needs all four" fields (two are required); a priority control the UI does not have; and a
   promise to "say so on the ticket" when priority is re-triaged, which the code makes impossible.

---

## 1. Inventory

`C` = `custom/db/documentation`. Words are **body words** (front matter excluded), whitespace tokens, counted with
Python. Registry keys are in `app/javascript/dashboard/helper/documentationLinks.js`.

| key | EN file | AR file | title (EN / AR) | position | EN words | AR words |
|---|---|---|---|---|---|---|
| `troubleshooting` | `C/en/troubleshooting/troubleshooting.md` | `C/ar/troubleshooting/troubleshooting.md` | When something is not working / عندما لا يعمل شيء | 10 | 859 | 747 |
| `contact-lynomia-support` | `C/en/…/contact-lynomia-support.md` | `C/ar/…/contact-lynomia-support.md` | Raising a ticket with Lynomia / فتح تذكرة مع لينوميا | 20 | 1000 | 806 |
| `commerce-store-needs-reconnecting` | `C/en/…/commerce-store-needs-reconnecting.md` | `C/ar/…/commerce-store-needs-reconnecting.md` | Your store needs to be reconnected / متجرك يحتاج إلى إعادة ربط | 60 | 460 | 355 |
| `commerce-store-unreachable` | `C/en/…/commerce-store-unreachable.md` | `C/ar/…/commerce-store-unreachable.md` | Lynomia cannot reach your store / لينوميا لا تستطيع الوصول إلى متجرك | 61 | 456 | 339 |
| `commerce-store-address-refused` | `C/en/…/commerce-store-address-refused.md` | `C/ar/…/commerce-store-address-refused.md` | The store address was refused / عنوان المتجر مرفوض | 62 | 404 | 332 |
| `commerce-keys-cannot-do-that` | `C/en/…/commerce-keys-cannot-do-that.md` | `C/ar/…/commerce-keys-cannot-do-that.md` | Your store keys cannot do that / مفاتيح متجرك لا تستطيع ذلك | 63 | 456 | 359 |
| `commerce-order-action-did-not-apply` | `C/en/…/commerce-order-action-did-not-apply.md` | `C/ar/…/commerce-order-action-did-not-apply.md` | An order action did not apply / إجراء طلب لم يُطبَّق | 64 | 601 | 436 |
| **section total** | 7 | 7 | | | **4236** | **3374** |

The section is the last of 12 (`manifest.yml:117-125`, position 110, icon `life-buoy`, EN "When something is not
working.", AR "عندما لا يعمل شيء كما ينبغي."). Article positions are 10, 20, 60–64; 30–50 are unused. Five of the
seven articles are commerce; the other two are the hub and the vendor desk. There is no troubleshooting article for
WhatsApp, Facebook, Instagram, email or the web widget in this section — WhatsApp has its own 14-article section
(`whatsapp-errors`, agent 054), and the others have none anywhere.

**Measurement hazard for every corpus agent (049–062).** In this shell's default POSIX locale `wc -w` counts Arabic
text roughly 4-5x low: `ar/…/commerce-keys-cannot-do-that.md` reports **89** words, while `LC_ALL=C.UTF-8 wc -w`
and `awk '{n+=NF}'` both report **415** (file including front matter). Any AR word count taken with plain `wc -w`
is wrong; the ratio AR/EN of 0.80 above is the true one.

**How readers reach each article** (inbound, computed from every `](key)` link in both locales plus the registry):

| key | inbound Markdown links (corpus) | inbound from the product |
|---|---|---|
| `troubleshooting` | 6 links from 4 articles, per locale (audit-logs, webhooks, your-first-conversation, contact-lynomia-support) | `troubleshooting` key (`documentationLinks.js:87`) |
| `contact-lynomia-support` | **0** (the hub does not link it) | `contactLynomiaSupport` (`:93`), three Help & Support pages |
| `commerce-store-needs-reconnecting` | **0** | `commerceStoreReconnect` via `commerceErrorArticle` only |
| `commerce-store-unreachable` | 2 (both from contact-lynomia-support) | same resolver |
| `commerce-store-address-refused` | **0** | same resolver |
| `commerce-keys-cannot-do-that` | **0** | same resolver |
| `commerce-order-action-did-not-apply` | **0** | same resolver |

`commerceErrorArticle` is consumed in exactly one place, the panel's read-error banner
(`CommercePanel.vue:406-417`, label "What to do about this", `commerce.json:55`). That banner shows `panel.error`,
which is a *read* error. The order-action dialogs, the Settings → Commerce store rows ("Needs re-authorization",
"Reconnect", "Replace keys") and the connect dialogs carry no link to any of the five (`rg DocsLink` under
`components/widgets/conversation/commerce` and `routes/dashboard/settings/commerce` finds only `CommercePanel.vue`
and the connect dialogs' own "how to connect" links; agent 043 logged the same in `_ARBITRATION.md` §CH). So the
action codes mapped at `documentationLinks.js:123-132` have a registry entry and no surface that uses it.

---

## 2. Per-article verdict

| key | verdict | reason | evidence |
|---|---|---|---|
| `troubleshooting` | **EXPAND** | The structure (four causes, then a symptom → first check → article table) is the best routing in the corpus and should stay. It needs a fifth cause (a connected store), links to the five commerce articles and to the ticket article, and corrections to two "nothing" rows. | §3.3 H6-H7; §1 inbound table; §5.2 |
| `contact-lynomia-support` | **SPLIT** | Three jobs in 1,000 words — how the desk works, what to put in a ticket, what a status means — and the product links all three questions to one URL with no anchor (`PlatformSupportNewPage.vue:79-82`, `PlatformSupportIndexPage.vue:148-151`, `PlatformSupportDetailPage.vue:280-283`; `DocsLink.vue:24-26` builds `href` from the key alone). Keep the key as the parent ("how the desk works"), add two keys. Four local defects need fixing in the same pass. The cheaper alternative is stable heading anchors plus an `anchor` prop on `DocsLink`; that is an IA decision (Phase 3), not a content one. | §3.3 S1-S10; `documentationLinks.js:88-93` records the one-article decision |
| `commerce-store-needs-reconnecting` | **REWRITE** | Wrong on-screen strings, one remedy stated for four platforms where three differ, a cause table that conflates uninstall (`disconnected`) with refresh failure (`needs_reauth`), a false "not a guess from a single failed request", and it advertises abandoned carts the sibling article says do not exist. | §3.2; §3.3 R2-R12; DC-15 |
| `commerce-store-unreachable` | **EXPAND** | The best-verified commerce article (timeouts, retry rule, stale fallback and "status unchanged" all confirmed). It needs the true strings, the 24-hour bound on the stale fallback, DNS and TLS as named causes, and the two codes the registry sends here that it never explains (`RATE_LIMITED`, `INVALID_RESPONSE`). | §3.3 U1-U11; `documentationLinks.js:112-115` |
| `commerce-store-address-refused` | **REWRITE** | Its examples do not produce its message; it says WooCommerce is the only platform where you type an address (Shopify also does, and gets the opposite advice); "no path" is wrong for a WordPress subfolder; port and bare-IP rules are not mentioned. | §3.3 A2-A7 |
| `commerce-keys-cannot-do-that` | **REWRITE** | Groups three codes with three different remedies under "keys" (a Shopify approval nobody on the customer side can obtain is not a key problem); its Shopify and Zid remedies target order actions that are held out of production; omits that a Read key also loses live updates and that "order actions off" has installation-level causes. Consider splitting `PROTECTED_DATA_NOT_APPROVED` into its own article. | §3.3 K2-K9; `switches.rb:16-26`; XA-02 |
| `commerce-order-action-did-not-apply` | **REWRITE** (table) / **KEEP** ("We do not know") | The conceptual core is right and unique in the corpus. Two table rows are wrong (`NOT_APPLIED`, `ACTION_UNAVAILABLE`), three are incomplete (`ACTIONS_DISABLED`, `ACTION_IN_PROGRESS`, `ORDER_CHANGED`), the opening "only thing Lynomia writes" is false, and `NOT_SENT`, `IDEMPOTENCY_CONFLICT` and the action-throttle `RATE_LIMITED` are mapped here and never explained. | §3.3 O1-O16 |

No article should be RETIRED or MERGED. **RELOCATE** is an open IA question, not a verdict: five of the seven
articles are commerce while a seven-article `commerce` section exists, and WhatsApp errors have their own section.
I recommend keeping the commerce articles here — the registry comment (`documentationLinks.js:87-93`) already argues
"that is where a stuck reader already is", the 31-code error surface collapses to five remedies and will not grow
the way Meta's does — and fixing the hub so it routes to them (agent 062 to decide).

## 3. Accuracy against the product

Verdict tokens are the template's: `confirmed`, `wrong`, `unverifiable`. Where a claim is right in one place and
wrong in another the verdict is `wrong` if a reader following the article would be misled, with the confirmed part
named. `en/commerce.json` below means `app/javascript/dashboard/i18n/locale/en/commerce.json`.

@@COUNTS@@

### 3.2 The "what you see" strings: 0 of 19 exist

Every one of the five commerce articles opens with a table whose left column is quoted as on-screen text. I
extracted all 21 curly-quoted items from the EN articles (19 are claimed on-screen strings; the other two are the
fragment “We do not know” and the illustration “last updated 40 minutes ago”) and tested each with `rg -F` over
the EN locale files: **0 matches**. The Arabic articles quote 27 «…» items that are translations of the English
ones; none of the 19 Arabic equivalents appears in `ar/commerce.json` (the four `rg` hits in the contact article are
single common words, not quotations). The panel never renders a code at all: `errorMessage` maps every code to a
sentence (`useCommerceLabels.js:54-89`), so the right-hand "The code behind it" column names identifiers that only
Lynomia's staff can see (`account.html.erb:192`).

| article:line | quoted as on screen | code | what ships (`en/commerce.json:line`) |
|---|---|---|---|
| unreachable:13 | “Your store did not answer” | `STORE_UNAVAILABLE` | "The store is not reachable right now." (:133) |
| unreachable:14 | “Your store took too long to answer” | `TIMEOUT` | "The store took too long to answer." (:137) — a near miss |
| unreachable:23-25 | “last updated 40 minutes ago” | stale fallback | the stale banner reads "Couldn't refresh store data right now." (:36) then "Last updated {time}" (:37) and **no error text** (`CommercePanel.vue:406-410`); the Customer 360 form is "Showing data from {time}" (:78) |
| reconnecting:18 | “This store needs to be reconnected” | `needs_reauth` | Settings chip "Needs re-authorization" (:190); Customer 360 "Store needs re-authorization" (:84); plus a per-platform hint (:260, :269, :281) |
| reconnecting:19 | “We could not reach your store” | `AUTH_INVALID` | "The store rejected {installationName}'s credentials. An administrator needs to reconnect the store." (:134). The article's string says *could not reach*, which is the opposite diagnosis from the one it is explaining (credentials, not connection) |
| keys:14 | “Your store refused that” | `PERMISSION_DENIED` | "The store refused access to its orders or customers. An administrator needs to check the store's permissions." (:135) |
| keys:15 | “These keys cannot change orders” | `WRITE_ACCESS_DENIED` | "The store's credentials can't change orders. An administrator can replace them." (:153) |
| keys:16 | “This store is not approved for customer data” | `PROTECTED_DATA_NOT_APPROVED` | "Shopify has not approved {installationName} to read this store's customer data (email and phone) yet, so customers can't be matched." (:145) |
| keys:17 | "Order actions greyed out, with a reason" | `read_only_key` / `missing_scope` | those are internal reason ids and are never displayed. Settings shows "Order actions require a Read/Write {provider} API key." (:301), "Additional {provider} permissions are required. Reconnect {provider} to enable order actions." (:302), "Order actions are switched off on this installation." (:303) (`Index.vue:211-233`) |
| address:14 | “That address is not a store we can reach” | `INVALID_STORE_URL` / private | "This address points to a private network and can't be used." (:172) |
| address:15 | “That address is not valid” | `INVALID_STORE_URL` / invalid | "Enter the store address, for example https://shop.example.com." (:168), and separately "The store must use https." (:169), "Custom ports are not supported." (:170), "Use the store's domain name, not an IP address." (:171) |
| address:16 | “That store redirected us somewhere else” | `INVALID_STORE_URL` / redirect | "The store redirected to another address. Enter the final store URL." (:173) |
| action:16 | “The order changed while you were looking at it” | `ORDER_CHANGED` | "The order changed in the store after you opened it. Nothing was sent. Review it again." (:150) |
| action:17 | “That did not apply” | `NOT_APPLIED` | "The store shows the change wasn’t made. You can try again." (:154) |
| action:18 | “Your store declined the refund” | `REFUND_DECLINED` | "The payment gateway refused the refund. No money was sent." (:156) |
| action:19 | “Your store refused that” | `PROVIDER_REJECTED` | "The store refused this change." (:155) |
| action:20 | “That action is already running” | `ACTION_IN_PROGRESS` | "Another action on this order is still being processed." (:149) |
| action:21 | “That amount is not valid” | `INVALID_AMOUNT` | "The amount isn’t valid for this order. Nothing was sent." (:151) |
| action:22 | “We do not know whether that applied” | unknown outcome | "The store didn’t answer in time. {installationName} is checking the order with the store: don’t try again until it does." (:408); if read-back runs out: "…couldn’t confirm the result with the store. Check the order in the store before trying again." (:409) |
| action:23 | “Order actions are turned off” | `ACTIONS_DISABLED` | "Order actions are off for this store." (:147) |
| action:24 | “That action is not available for this store” | `ACTION_UNAVAILABLE` | "This action isn’t possible for the order right now." (:148), and the per-action menu reasons (:350-361) |

What the real strings carry that the articles lose: **"Nothing was sent."**, **"No money was sent."** and **"don't try
again until it does"**. Those are the three reassurances an agent most needs while a refund is on screen, and they
are exactly the facts Lynomia *knows*.

Search consequence (agent 077's area): the portal search matches article text, and a reader pastes what they see.
The shipped sentences appear nowhere in the corpus, so the article cannot be found by the string that links to it.

### 3.3 Claims checked, per article

**Hub — `troubleshooting.md` (EN line numbers)**

| # | line | claim | verdict | evidence |
|---|---|---|---|---|
| H1 | 20-23 | A custom role's permission list has no entry for inboxes, channels, campaigns, WhatsApp templates, flows, automation rules or audiences | confirmed | `custom/app/models/custom_role.rb:19-27` — closed list: `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`, `contact_manage`, `report_manage`, `commerce_order_manage`, `support_ticket_manage`, `knowledge_base_manage` |
| H2 | 32 | An inbox has an **Account Health** tab | confirmed (WhatsApp Cloud and Twilio inboxes) | `routes/dashboard/settings/inbox/Settings.vue:254,264`; `en/inboxMgmt.json:792`. It is the one "first check" in the hub that shows provider state Lynomia *asked for* (its error copy says "Meta could not return the current health details", `inboxMgmt.json:945`) |
| H3 | 40 | A flow needs a WhatsApp Cloud inbox | confirmed | `custom/app/services/flows/channel_capabilities.rb:2-3,19-22` |
| H4 | 55 | Flows keep **Sessions** | confirmed | `routes/dashboard/settings/flows/FlowBuilder.vue:38,519` |
| H5 | 57 | Audit logs cover "fourteen event types" | unverifiable | not counted by me; agrees with `administration/audit-logs.md:20` (agent 059) |
| H6 | 58 | Automation rules: "nothing. There is no run history and no per-rule log in the product" | confirmed (tenant surfaces) | no UI. But Lynomia writes one structured line per evaluation with outcome `executed`/`skipped`/`duplicate`/`no_conversation`, `rule_id` and a correlation id (`custom/app/services/automation/execution_log.rb:1-15`). The honest advice is "quote the rule id, time and conversation in a ticket", which the hub never says. Whether the desk reads application logs: unverified |
| H7 | 59 | Webhooks: "nothing. No delivery log, no retry, no replay" | wrong (in part) | right for account webhooks: failure is logged and swallowed (`lib/webhooks/trigger.rb:26-35`). Not right as a blanket: an API-inbox webhook failure marks the message **failed** (`trigger.rb:65-67,100-102`); an agent-bot failure moves the conversation to open with an activity note (`trigger.rb:77-98`) and 429/500 are retried (`trigger.rb:3,125-126`) |
| H8 | 69 | Messages sent while the webhook was missing "are gone. There is no backfill" | unverifiable (Meta) | no backfill or replay exists in the repo (`rg` for backfill, history sync and missed-message handling over `app/services/whatsapp`, `custom/app/services/whatsapp` and the job directories finds nothing relevant). "Gone" is a statement about Meta's redelivery behaviour, which Lynomia cannot know — route to 026/088 |
| H9 | 70-73 | Automation has no business-hours, time-of-day or working-hours condition | confirmed | `routes/dashboard/settings/automation/constants.js:12-84` and every other condition list: no time attribute; the only "hours" hit is a delay default (`:815`) |
| H10 | 73 | Refunds and cancellations cannot be delegated to a custom role | confirmed | `custom/app/policies/commerce/action_policy.rb:6,23-29` (administrators only); `en/commerce.json:ORDER_ACTIONS_HINT` |
| H11 | 77-79 | Account Health, inbox configuration, templates, campaigns, automation and audit logs are administrator-only | unverifiable | other agents' routes (053, 055, 057, 059); not checked here |

**Support — `contact-lynomia-support.md`**

| # | line | claim | verdict | evidence |
|---|---|---|---|---|
| S1 | 8 vs 11-15 | "There are two different support desks in this product" above a table of **three** desks | wrong | the article contradicts itself; AR the same (`مكتبا دعم` above three rows). Reads as "your two vs Lynomia's one", but the table never says so |
| S2 | 13-19 | Path is **Help & Support → My tickets / New ticket** | confirmed | `components-next/sidebar/Sidebar.vue:738-760`; `en/settings.json:405-409`; `en/platformSupport.json` SIDEBAR; never feature-gated (`Sidebar.vue:743`, `help.routes.js:21`) |
| S3 | 21 | "Four things are asked, and a ticket needs all four" | wrong | only **subject** and **description** are required (`NewTicketForm.vue:86-88`; `tickets_controller.rb:62-66`); category defaults to "Something else" and priority to Medium (`help/constants.js` `PLATFORM_SUPPORT_DEFAULT_CATEGORY`/`_PRIORITY`). The form's labels are "What is this about?" and "How urgent is this?", not "Category" and "Priority" (`platformSupport.json` FORM.CATEGORY, FORM.PRIORITY) |
| S4 | 27-28 | "Urgent means the service is down for you. Everything else is High or below" | confirmed | `platformSupport.json` FORM.PRIORITY_HINT, ENUMS.PRIORITY.URGENT |
| S5 | 30-32 | Up to 5 files of 10 MB; images, PDF, plain text, CSV; archives refused | confirmed | `custom/app/models/platform_support/message.rb:32-34` (png, jpeg, gif, webp, pdf, text/plain, text/csv; `MAX_FILES = 5`; `10.megabytes`); `base_controller.rb:62-89`. Note: a billing-locked customer cannot upload them — PD-34 |
| S6 | 34-35 | Reference looks like `LYN-000123`; you land on the ticket; you get an email on a reply | confirmed | `ticket.rb:46-47,90-92`; `PlatformSupportNewPage.vue:46-50`; `message_creation.rb:135-145`, `ticket_mailer.rb` `operator_replied` (reporter and the account's administrators). Email failure is logged, not surfaced (`ticket_mailer.rb` header), and an in-app bell row is written too (`reply_notifier.rb:1-30`) |
| S7 | 51-58 | The six status names and meanings | confirmed | `ticket.rb:26`; `platformSupport.json` ENUMS.STATUS and STATUS_SENTENCE — the article is word-for-word the product's own sentences |
| S8 | 62-63 | Replying to a resolved ticket reopens it; a closed ticket takes no replies | confirmed | `message_creation.rb:7-10,37,75-83`; `platformSupport.json` REPLY.REOPENS_HINT, DETAIL.CLOSED_HINT |
| S9 | 65-66 | "You can change a ticket's priority at any time… we may re-triage it, and we will say so on the ticket when we do" | wrong | the API accepts `priority` (`tickets_controller.rb:9-10,72-78`) but the detail page renders priority as a read-only chip (`PlatformSupportDetailPage.vue:226-230`) and no other control exists. And a staff re-triage is **not shown to the customer**: `priority_changed` and `category_changed` are excluded from the customer-visible event list (`event.rb:9-11,26-27`; `ticket_transition.rb:12-15`) and re-triage writes no message |
| S10 | 87-88 | The hub "sorts most reports into one of four causes… and three of them you can fix yourself" | wrong | contradicts the hub: plan or installation switch — "nothing in your account changes those" (hub 25-26); Meta — "cannot appeal or override" (hub 67-68); a role — an administrator changes it, not you. Only "configuration" is self-fixable. AR repeats it (`وثلاثة منها تستطيع إصلاحها بنفسك`) |
| S11 | 70-71 | The desk covers billing, access, channels, WhatsApp, store and orders, campaigns, automation, slowness, data export, "anything that looks broken" | confirmed | exactly the 11 categories (`ticket.rb:38-39`; ENUMS.CATEGORY). Note that only some have articles — §4 |
| S12 | 76 | "we never read or answer [your customers' conversations]" | unverifiable | a vendor policy, not a mechanism the repo can show; staff surfaces read account snapshots (`operations/account_snapshot.rb`), message-body access by staff was not checked |
| S13 | 90-94 | A billing-locked account can still raise a ticket; suspended accounts cannot | confirmed (API) | `base_controller.rb:16-23,29-31` (`billing_exempt?` true; suspension answers 401 one layer earlier). The browser path for a locked account was not exercised |
| S14 | 94 | "a suspension notice says who to contact" | wrong (in part) | the notice says "please contact our support team" and names no contact (`en/settings.json:271`) |
| S15 | 98-103 | Administrators see every ticket for the account; an agent or custom role sees only their own | confirmed | `custom/app/policies/platform_support/ticket_policy.rb:4-6,44-50` (a custom-role holder falls to the agent branch by design, `:8-13`) |
| S16 | 106-109 | Internal notes stay internal | confirmed | `ticket.rb:57-62`; `message.rb:4-6`; `reply_notifier.rb:5-8` (no tenant route, serializer or mailer names a note) |
| S17 | — | (absence) no response-time promise is made | confirmed | the article makes none, which is correct: no `SlaPolicy` row can be created through the product (PD-02), so any figure would be invented |

**Needs reconnecting — `commerce-store-needs-reconnecting.md`**

| # | line | claim | verdict | evidence |
|---|---|---|---|---|
| R1 | 8-10 | In this state order history does not load, carts stop arriving, actions are unavailable; nothing retries | confirmed, with a contradiction | `customer360.rb:90` (listed without being read), `realtime.rb:40,49,72` and `abandoned_carts.rb:19` (`store.active?`), `token_manager.rb:64`. But "abandoned carts stop arriving" advertises a feature the corpus says does not exist: `commerce/commerce-overview.md:52` "not available on any platform", `commerce-provider-support.md:76` "there is no abandoned-cart feature" (held: `switches.rb:16`) |
| R2 | 12 | "Only an administrator can fix it, and it takes one action: Settings → Commerce → the store → **Reconnect**" | wrong | administrator-only is right (`commerce.routes.js:19`). The one action is not: WooCommerce shows **Replace keys** (`Index.vue:495-503`); Salla shows **no button** and a hint to update or reinstall the app from the Salla dashboard (`Index.vue:93-97,438-443`; `en/commerce.json:260`); only Zid and Shopify show **Reconnect** (`Index.vue:34,507-513`). DC-15 |
| R3 | 21-22 | The status "is durable… written the moment the store refused the access… not a guess from a single failed request" | wrong | WooCommerce: one 401 on one panel read, search, cart read or action read flips the status (`conversation_panel.rb:121`, `order_search.rb:37`, `abandoned_carts.rb:36`, `order_actions.rb:98` → `store_connection.rb:80-86`). Zid and Shopify: one refresh plus one retry (`token_manager.rb:19-28,55-61`). Salla: a refresh whose outcome is *unknown* is treated as spent and sets the status (`salla/token_manager.rb:1-12,57-62`) — a defensive guess by design |
| R4 | 29-30 | WooCommerce: "the API key was deleted, or its permissions were changed" | unverifiable (provider), partly contradicted | Lynomia received HTTP 401 (`http_client.rb:225`). A permissions change on a key that can still read does not produce `AUTH_INVALID`; on a write it produces `WRITE_ACCESS_DENIED` (`woocommerce/actions.rb:147,155-158`). Another cause of a 401 — a host or plugin stripping the Authorization header — is indistinguishable to Lynomia |
| R5 | 31-33 | Salla: "uninstalled or its authorization lapsed"; reinstalling reconnects on its own; no new code needed unless the store left the list | wrong (in part) | a lapse: right — a reinstall or update re-authorizes a `needs_reauth` store automatically (`salla/installation.rb:32-45,115-121`; `en/commerce.json:260`). An **uninstall**: the `app.uninstalled` event **disconnects** the store (`installation.rb:76-82`), and a reinstall then waits for a new connection code because `connected_store` excludes disconnected rows (`installation.rb:123-125`) |
| R6 | 34-36 | Zid answers a rejected authorization with a redirect to its login page; the product treats it as rejected | confirmed | `custom/app/services/commerce/providers/zid.rb:160-161` |
| R7 | 37 | Shopify: "uninstalled from the store's admin, or the access revoked" | wrong (in part) | an uninstall is a signed webhook that **disconnects** the store, removing token, links and cache (`shopify/webhook_job.rb:42-46`; `store_connection.rb:98-107`). `needs_reauth` for Shopify comes from a refused refresh token or from the refresh token **expiring** (`shopify/token_manager.rb:10-11,28`) — which needs nobody to have done anything. The "two can happen without anybody doing anything wrong" sentence never says which two |
| R8 | 43-44 | On entering this state the store's access and cached data are removed | wrong (in part) | cache purged — confirmed (`token_manager.rb:113`, `store_connection.rb:84`). Access removed — only for OAuth providers (`token_manager.rb:111`; Salla removes the refresh token only, `salla/token_manager.rb:86`). WooCommerce keys stay stored: `credentials_rejected` changes the status and purges the cache, nothing else (`store_connection.rb:80-86`) |
| R9 | 45-48 | "disconnecting does not delete your history"; conversations, contacts and action history stay | wrong (in part) | right for conversations and contacts. **Disconnect deletes the customer links** (`store_connection.rb:98-107`; `salla/installation.rb:75`) — which is why Customer 360 then says "Customer not linked" |
| R10 | 47-48 | Reconnecting a disconnected store "rather than counting against your plan's store limit twice" | wrong (in part) | disconnected rows are not counted (`store.rb:45` `connected` scope; `store_connection.rb:4-7`), but a reconnect is checked against the limit and can be refused with `STORE_LIMIT_REACHED` (`store_connection.rb:130-134`). That code shows the generic "Something went wrong" string today (PD-25) |
| R11 | 52-54 | "If the store moves back into this state within minutes of reconnecting… it is a permissions problem rather than an authorization one" | wrong | permissions problems produce `PERMISSION_DENIED` (403) or `WRITE_ACCESS_DENIED`, never `AUTH_INVALID`/`needs_reauth` (`http_client.rb:225-226`; `woocommerce/actions.rb:147`). A flapping store points to an intermittent 401 or to the Salla refresh path, not to permissions |
| R12 | — | (omission) Lynomia-side causes of this state | gap | `refresh_interrupted`, `refresh_outcome_unknown`, `refresh_response_invalid`, `refresh_http_N` (Salla); `zid_login_redirect`, `refresh_response_invalid` (Zid); `refresh_token_expired` (Shopify) — all recorded in the audit trail as the reason (`token_manager.rb:114`; `salla/token_manager.rb:89`), none mentioned |

**Cannot reach your store — `commerce-store-unreachable.md`**

| # | line | claim | verdict | evidence |
|---|---|---|---|---|
| U1 | 13 | `STORE_UNAVAILABLE` = the connection failed or the store returned a 5xx | confirmed, incomplete | `http_client.rb:229,237`. The same code also covers **DNS failure** (`:156-157`, reason `dns`) and **TLS failure** (`:237`, reason `tls`), so a mistyped domain or an expired certificate reads as "not reachable". Neither is named |
| U2 | 14 | `TIMEOUT` = "the request was sent and no answer arrived inside the limit" | wrong (in part) | on a read, a **connect** timeout also becomes `TIMEOUT` although nothing was sent (`http_client.rb:160-161`), as does the 10 s body deadline (`:205`). On an action a connect timeout is `STORE_UNAVAILABLE`/`not_sent` (`:24-26,122-123`) |
| U3 | 18-19 | 3 s connect, 8 s answer, 10 s body | confirmed | `http_client.rb:15,18`. Not said: an **order action** waits 25 s (`:17`) |
| U4 | 20-22 | One retry, reads only, on a dropped connection or 502/503/504; a timeout is not retried; an action never | confirmed | `http_client.rb:20-23,67-71,135-150` |
| U5 | 23-25 | The panel serves cached history labelled with its age | confirmed, incomplete | `cache.rb:1-3,23-27`; label `CommercePanel.vue:407`. Omitted: the fallback is only for `STORE_UNAVAILABLE`, `TIMEOUT`, `RATE_LIMITED`, `INVALID_RESPONSE` and only up to **24 hours** old (`cache.rb:9-10`). After that the panel is blank, not stale |
| U6 | 26-27 | An unreachable store stays `active` | confirmed | the only path to a status change is `AUTH_INVALID` (`conversation_panel.rb:121`; `store_connection.rb:80-86`) |
| U7 | 33-35 | A private-network store is refused rather than tried | confirmed | `http_client.rb:154-155` |
| U8 | 36-38 | A host that throttles unfamiliar traffic "will refuse us consistently while a browser works… is not [a product bug]" | unverifiable (provider) | Lynomia sends one fixed `User-Agent: Lynomia-Commerce/1.0` (`http_client.rb:29`) and cannot see the host's rule; the sentence asserts the cause as certain |
| U9 | 39-40 | A store that answers in 12 s "will time out here every time" | confirmed | follows from `http_client.rb:15,18` |
| U10 | 44-45 | "There is no cache to clear by hand" | confirmed, but | there is a **Refresh** button with a cooldown (`en/commerce.json:38`; `cache.rb:14` `force`), which the article does not mention |
| U11 | — | (omission) `RATE_LIMITED` and `INVALID_RESPONSE` are mapped here | gap | `documentationLinks.js:114-115`. A 429 from the store, a non-JSON or oversized answer (`http_client.rb:204,219,228,230`) — typically a WAF challenge page or a maintenance page — are the likeliest real causes of "it works in my browser" and are not described |

**Address refused — `commerce-store-address-refused.md`**

| # | line | claim | verdict | evidence |
|---|---|---|---|---|
| A1 | 8-9 | Refused before any request leaves Lynomia, or when the store answers with a redirect | confirmed | `store_url.rb:3-4`; `http_client.rb:5-7,224` |
| A2 | 9-10 | WooCommerce "is the only platform where you type an address — Salla, Zid and Shopify provide their own" | wrong | **Shopify asks you to type the store's `myshopify.com` domain** (`ShopifyConnectDialog.vue:86-91`; `en/commerce.json:277-278`) and refuses a bad one with `INVALID_STORE_URL` / `shopify_domain` (`shopify_connections_controller.rb:25-26`; "Enter the store's myshopify.com domain…", `en/commerce.json:174`). The article's advice — "use the real public address, the one a customer would type" — is the **opposite** for Shopify: a custom storefront domain is rejected on purpose (`shop_domain.rb:13-15`). The registry sends every `INVALID_STORE_URL` here (`documentationLinks.js:117`) |
| A3 | 24-27 | `http://localhost`, `http://192.168.x.x`, `http://10.x.x.x` and a `.local` host "are all refused" by the private-address rule | wrong | refused, but each by an earlier rule with a different message: any `http://` scheme → "The store must use https." (`store_url.rb:33`; `en/commerce.json:169`); a bare IP over https → "Use the store's domain name, not an IP address." (`store_url.rb:35`; `:171`); an unresolvable `.local` name → `STORE_UNAVAILABLE`/`dns` = "The store is not reachable right now." (`http_client.rb:156-157`). The "private network" message (`:172`) appears only for a **hostname that resolves to a private address** — none of the four examples |
| A4 | 20-22 | The connection is pinned to the address it checked | confirmed | `http_client.rb:5-6,180` |
| A5 | 31-38 | Redirects are never followed | confirmed | `http_client.rb:7,180,224` |
| A6 | 42-43 | `http` is possible only where "an administrator of this installation" listed the host as a development store | confirmed, misleading | mechanism is the **operator-only environment variable** `COMMERCE_TRUSTED_STORE_HOSTS` (`store_url.rb:5-6,14-16,33`). A customer administrator cannot do this; "administrator of this installation" reads as the account admin |
| A7 | 45 | "no path: not /wp-json, not /wp-admin, not a trailing page" | wrong (in part) | a path is allowed and used — a WordPress in a subfolder (`https://example.com/shop`) is a supported address (`store_url.rb:21-24,53-56`; `http_client.rb:129-131`; `woocommerce.rb:9`). Only a trailing `/wp-json` is wrong |
| A8 | — | (omission) port and bare-IP rules and the https message | gap | `store_url.rb:33-35`; `en/commerce.json:169-171` |

**Keys cannot do that — `commerce-keys-cannot-do-that.md`**

| # | line | claim | verdict | evidence |
|---|---|---|---|---|
| K1 | 8-10 | Lynomia "never quietly upgrades the access you granted" | confirmed | `providers/base.rb:68-70`; `store_connection.rb:66-69` |
| K2 | 21-24 | WooCommerce: `read_only_key` is recorded "the first time a write is refused" | wrong (in part) | it is also recorded at connect time when webhook registration is refused (`woocommerce.rb:94-108`), and a store that never proved write access reports `write_access_unverified` (`woocommerce.rb:25-28`) which the UI shows with the **same** "require a Read/Write key" sentence (`Index.vue:218-222`). A reader with a genuine Read/Write key can see the message and be told their key is read-only |
| K3 | 24-26 | Create a new Read/Write key in WordPress → WooCommerce → Settings → Advanced → REST API; "an existing key's permissions cannot be raised in place" | unverifiable (provider) | WooCommerce UI and behaviour; I recall the key edit screen exposing Permissions, so treat as suspect and verify with 045 against WooCommerce's docs or a test store |
| K4 | 27-28 | Shopify: order actions need `write_orders`; without it `missing_scope`; reconnecting re-requests scopes | wrong in production | code is consistent (`shopify.rb:126-129`; `Index.vue:464-472`) but Shopify order actions are `PRE_UAT`-held (`switches.rb:16`), and `provider_actions_enabled?` is checked **before** the scope (`order_actions.rb:103-110`), so a production Shopify store reports `provider_actions_disabled`, never `missing_scope`, and the "Reconnect for order actions" button never appears. `commerce-provider-support.md:75` says exactly this |
| K5 | 29-30 | Zid: "the same shape… records `missing_scope`" | wrong in production | same: `PRE_UAT` (`switches.rb:16`). Also Zid supports one action only — shipped/delivered status changes (`zid/actions.rb:2-9`) — and learns `missing_scope` from a bare 403 because "Zid publishes no list of granted scopes" (`zid/actions.rb:11-12,39`): an inference |
| K6 | 31-32 | Salla is read-only by design; no order actions | confirmed | `providers/salla.rb:3`; `providers/base.rb:66` |
| K7 | 34-39 | Shopify needs an app approved before it may read customer names, emails, phones; until then the store works for everything else | confirmed (Lynomia side) / unverifiable (Shopify policy) | classified from Shopify's own ACCESS_DENIED wording by regex (`shopify/graphql.rb:60-65`). Not a keys problem and not fixable by the merchant — it needs Lynomia's app approval, which the article does not say |
| K8 | 41-46 | Order actions are off per store by default; turning them on requires credentials that can write | confirmed, incomplete | `order_actions.rb:103-110`; `store_connection.rb:70-71`; toggle `Index.vue:448-463`. Omits two installation-level reasons for the same refusal (§3.3 O10) |
| K9 | 21-23 | A Read key "is exactly right if you only want order history in conversations" | wrong (in part) | a Read key also loses **live order updates** (`en/commerce.json:185`; `woocommerce.rb:98-107`; `commerce-provider-support.md:94`), which the article never mentions |

**Order action did not apply — `commerce-order-action-did-not-apply.md`**

| # | line | claim | verdict | evidence |
|---|---|---|---|---|
| O1 | 8-9 | An order action "is the only thing Lynomia **writes** to your store" | wrong | on WooCommerce Lynomia also creates and deletes its own webhooks in the store with the key (`woocommerce.rb:94-108,112-118,153-160`); the Settings hint says so: "Lynomia only adds its own webhooks" (`en/commerce.json:218`). `commerce-provider-support.md:47` repeats the same overstatement |
| O2 | 9-10 | A write is never sent twice | confirmed | `http_client.rb:67-71`; `action_executor.rb:5-9,49-55` |
| O3 | 16 | `ORDER_CHANGED` = "somebody else changed the order" | confirmed (event) / wrong (cause) | `action_executor.rb:80`: the order's fingerprint (status, total, currency, paid date, payment method, refunds — `woocommerce/actions.rb:192-195`) differs from the one the agent confirmed. Lynomia cannot know *who*; a payment, a store automation or Lynomia's own earlier action all change it. The shipped string adds "Nothing was sent." |
| O4 | 17 | `NOT_APPLIED` = "the store accepted the request and the order is provably unchanged" | wrong | `NOT_APPLIED` exists only as the verdict of a **read-back after the answer was lost** (`action_executor.rb:120`). Lynomia never learned that the store accepted anything — it lost the answer, then at least 5 minutes later (`SETTLED_AFTER`, `woocommerce/actions.rb:37,70,164,176`; `shopify/actions.rb:49,187`) saw the order unchanged. With read-backs at 30 s, 2 min and 10 min (`action_executor.rb:15`) only the last can produce it |
| O5 | 18 | `REFUND_DECLINED` = "the payment gateway refused, not the store" | unverifiable (provider) | inferred from one WooCommerce answer: HTTP 500 with body code `woocommerce_rest_cannot_create_order_refund` (`woocommerce/actions.rb:33,149`). Nothing else produces it, so it is WooCommerce-only. Lynomia never holds the store's own reason (`action_result.rb:6`: "never the store's own error text"). The shipped string adds "No money was sent." |
| O6 | 19 | `PROVIDER_REJECTED` — "usually in a state that does not allow it" | unverifiable | Lynomia saw a 400/403/409/422 (`woocommerce/actions.rb:31-32`) or Shopify `userErrors` (`shopify/actions.rb:69,82,146`); "usually" is a guess |
| O7 | 20 | `ACTION_IN_PROGRESS` = "the same action is in flight" | wrong (scope) | any unresolved earlier action on the **order** blocks every other action on it (`order_actions.rb:13,161-163`), until reconciliation is exhausted |
| O8 | 21 | `INVALID_AMOUNT` = outside what the order allows | confirmed | reasons `currency`, `precision`, `above_refundable`, `not_full` (`action_executor.rb:102-111`) |
| O9 | 22, 26-42 | Unknown outcome: read back later, judge by what the store says now, otherwise stay unknown, never re-send | confirmed | `action_executor.rb:141-151`; timings 30 s / 2 min / 10 min (`:15`). One honest caveat the article lacks: for a status change, "in the target state" is read as success (`woocommerce/actions.rb:68-69`), which cannot tell Lynomia's write from someone else's identical change |
| O10 | 23 | `ACTIONS_DISABLED` = "the switch is off for this store; an administrator turns it on" | wrong (incomplete) | three different causes share the code (`order_actions.rb:26-30,103-110`): the installation kill switch, the per-provider switch (held for Salla, Zid, Shopify — `switches.rb:16,21-26`), and the store opt-in. Only the last is an account administrator's to change. The UI already distinguishes it: "Order actions are switched off on this installation." (`en/commerce.json:303`; `Index.vue:227-229`) |
| O11 | 24 | `ACTION_UNAVAILABLE` = "the platform does not support it — nothing; it is a capability, not a fault" | wrong | it is also raised when the order's **state** no longer allows the action (`action_executor.rb:82-83`), and the menu explains the fixable cases: "The order is paid: refund it first.", "Nothing is left to refund.", "The order was paid in more than one payment, so refund it in your store's admin." (`en/commerce.json:352,355,359`) |
| O12 | 34-37 | Read back later and judge only by what the store says now | confirmed | `action_executor.rb:34-44,153-160` |
| O13 | 46-50 | "every one is recorded with who ran it and what the store answered" | wrong (in part) | recorded: who, action, order, status and Lynomia's outcome code (`action_run.rb:78-81`). **Not** the store's answer — responses are never stored (`http_client.rb:13`; `action_result.rb:6`) |
| O14 | 46-48 | Off per store; need write credentials; checked against the order as the agent saw it | confirmed | `order_actions.rb:103-110`; `action_executor.rb:80` |
| O15 | — | (omission) codes mapped to this article but never explained | gap | `NOT_SENT` ("Nothing changed; you can try again", `en/commerce.json:164`), `IDEMPOTENCY_CONFLICT`, and `RATE_LIMITED` as Lynomia's own throttle (10/min/user, 30/min/store, 5/10 min/order, `order_actions.rb:25,218`; shipped string `ACTIONS.RATE_LIMITED`, `en/commerce.json:335`) — which the registry sends to the *unreachable* article (`documentationLinks.js:114`), because one code means both "the store limited us" and "Lynomia limited you" |

### 3.4 Provider state the article states and Lynomia never received

The brief's third question. Lynomia has three kinds of knowledge: what it **recorded** (an HTTP status, its own
timeout, a status flag, a counter), what it **inferred** (a classification from a code or a pattern), and what only
the **provider** knows. The articles routinely write the second and third in the voice of the first.

| article:line | the sentence | what Lynomia actually has | class |
|---|---|---|---|
| action:17 | `NOT_APPLIED`: "the store accepted the request" | nothing — the answer was lost; it read the order back ≥5 min later (`action_executor.rb:120`) | provider-side, never received |
| reconnecting:29-30 | WooCommerce "key was deleted, or its permissions were changed" | HTTP 401 (`http_client.rb:225`) | inferred, stated as fact |
| reconnecting:31-33 | Salla "uninstalled or authorization lapsed" | a refused refresh, or a refresh whose outcome is unknown (`salla/token_manager.rb:57-62`) | inferred; unknown-outcome is a guess by design |
| reconnecting:37 | Shopify "uninstalled… or revoked" | a refused refresh or an expired refresh token (`shopify/token_manager.rb:28`); an uninstall *is* received, as a webhook, and routes elsewhere | inferred / misrouted |
| reconnecting:21-22 | "not a guess from a single failed request" | for WooCommerce, exactly a single failed request (`conversation_panel.rb:121`) | recorded, mis-described |
| action:18 | `REFUND_DECLINED`: "the payment gateway refused" | one WooCommerce error code on an HTTP 500 (`woocommerce/actions.rb:149`) | inferred, WooCommerce-only |
| action:16 | `ORDER_CHANGED`: "somebody else changed" | a different order fingerprint (`action_executor.rb:80`) | recorded fact, invented author |
| action:19 | `PROVIDER_REJECTED`: "usually in a state that does not allow it" | a 4xx (`woocommerce/actions.rb:31-32`) | guess |
| keys:29-30 | Zid "authorization does not include order management" | a 403 (`zid/actions.rb:11-12,39`) | inferred |
| keys:24-26 | "an existing key's permissions cannot be raised in place" | nothing | provider-side, unverifiable |
| unreachable:36-38 | host throttling "is not [a product bug]" | a failed request and a fixed User-Agent | provider-side, asserted as certain |
| support:65-66 | "we will say so on the ticket" | the event is internal-only (`event.rb:9-11,26-27`) | a promise the code breaks |
| hub:69 | webhook-gap messages "are gone" | no backfill in the repo; Meta's redelivery unknown | provider-side |

Contrast: the places where the section is honest are exactly the places where Lynomia *does* have the fact — "A
store that cannot be reached stays `active`" (recorded), "We do not know whether that applied" (recorded and
named), "Reconnecting does not start you from scratch" (recorded) — and the places where it is not are all
provider-side or inferred. Two repository comments say the rule out loud and the articles do not follow it:
`delivery_failure.rb:10-11` ("transcribing Meta's catalogue from memory would be inventing policy that nothing here
can stand behind") and `diagnosis/local_checks.rb:28-30` ("neither can be inferred from the other").

What Lynomia *does* hold and the articles never offer the reader: a per-store health snapshot — last error code and
reason, consecutive failures, last success, last webhook received and processed
(`store_health_recorder.rb:39-47,54-62`) — visible to Lynomia's operators as "Provider failing (CODE)", "Last
answered N ago", "N failures in a row" (`operations/account.html.erb:192-197`, `commerce.html.erb:103`). A reader
who knows that exists will put the store name and the time in a ticket; today nothing tells them.

### 3.5 Where sibling articles contradict this section

| this section | other article | contradiction |
|---|---|---|
| reconnecting:8-9 "abandoned carts stop arriving" | `commerce-overview.md:52`, `commerce-provider-support.md:76` | those say there is no abandoned-cart feature (held, `switches.rb:16`; see also DC-11) |
| action:8-9 "the only thing Lynomia writes" | `commerce-provider-support.md:47` | same overstatement in both; WooCommerce webhooks are also written |
| keys:27-30 Shopify and Zid order-action remedies | `commerce-provider-support.md:75` "Only WooCommerce order actions can be used" | the troubleshooting article describes fixes for a feature the provider article says is unavailable (XA-02 is the editorial decision) |
| support:87-88 "three of them you can fix yourself" | hub:25-26, 65-68 | self-contradiction across the pair |
| hub:11-16 "four causes" | the section's own five commerce articles | a fifth cause (a connected store) is documented but not in the taxonomy |

## 4. Missing articles

What a stuck reader of this section cannot find, with the evidence that the question is real. "Unmapped" means the
code has a shipped string but no entry in `COMMERCE_ERROR_ARTICLES` (`documentationLinks.js:108-133`).

| # | the user's question | evidence it is asked | note |
|---|---|---|---|
| M1 | My store says **Disconnected**. What happened, what is kept, and how do I reconnect on my platform? | status exists (`en/commerce.json:191`); Shopify and Salla uninstalls land here, not in `needs_reauth` (`shopify/webhook_job.rb:42-46`, `salla/installation.rb:76-82`); `canReconnect` offers it per platform (`Index.vue:93-97`) | the reconnect article misfiles this state (§3.3 R5, R7); links are deleted on disconnect (R9) |
| M2 | I cannot connect a store: "already connected", "all the stores your plan allows", "turned off on this installation", "encryption is not configured" | `STORE_ALREADY_CONNECTED`, `PROVIDER_DISABLED`, `ENCRYPTION_NOT_CONFIGURED`, `STORE_LIMIT_REACHED` (`en/commerce.json:142-144,165`); all unmapped; `STORE_LIMIT_REACHED` is not even in `errorMessage`, so the admin sees "Something went wrong" (PD-25) | the string must ship before an article can quote it |
| M3 | A recovery message was not prepared ("sent recently", "can't receive a free-form message", "not safe to send") | `RECOVERY_DISABLED`, `RECOVERY_COOLDOWN`, `CANNOT_REPLY`, `INVALID_RECOVERY_URL`, `CART_NOT_ABANDONED` (`en/commerce.json:159-163`); unmapped | **blocked on XA-02**: the feature is held and the corpus says it does not exist. Do not write until that editorial rule is decided |
| M4 | An order action says it is "checking", or "couldn't confirm the result". Is it safe to try again? | `ACTIONS.RESULT.UNKNOWN`/`UNRESOLVED`/`STILL_PROCESSING` (`en/commerce.json:408-410`); `UNKNOWN_OUTCOME` is **not** in the registry mapping, and the action dialogs carry no link | content exists (the "We do not know" section); the missing piece is a registry key and a link from the dialog |
| M5 | My account is locked for billing. What stops working and how do I unlock it? | `Billing::AccessGuard` (`custom/app/controllers/billing/access_guard.rb:22,50`); the support article spends five lines on it (S13); no billing article exists in the corpus (`rg` finds billing only inside WhatsApp pages) | cross-section (059); the symptom belongs in the hub |
| M6 | I cannot sign in, lost my authenticator, or my invited colleague cannot join | ticket category `account_access` ("Account access", `platformSupport.json` ENUMS.CATEGORY); `rg` for password, 2FA, locked-out finds only the invite and connect pages | cross-section (049/059) |
| M7 | Something is slow. / How do I get my data out? | ticket categories `performance` and `data_export`; the support article lists both as covered (S11) with nothing to read first | the honest article is short: what the desk can and cannot do, and what to send |
| M8 | My Facebook, Instagram, email or web-chat inbox stopped working | the hub's symptom table has WhatsApp rows only (hub 32-36); orphaned i18n that would have been the help — `INBOX.REAUTHORIZE.TROUBLESHOOTING.*`, `INBOX_MGMT.DETAILS.ERROR_FB_UNAUTHORIZED` (`_ARBITRATION.md` §CH; 034/039/041) | wait for 041/042 on what is true before writing |
| M9 | What do I send when I ask for help with a store, an order action, a campaign? | every commerce article dead-ends; the ticket article's checklist is generic (support 37-45) | not a new article — a mandatory block in each troubleshooting article (§5.4, element 8) |

Two codes are mapped and unexplained inside articles that exist: `RATE_LIMITED` and `INVALID_RESPONSE` in the
unreachable article (U11) and `NOT_SENT`, `IDEMPOTENCY_CONFLICT` in the order-action article (O15). Those are
EXPAND work on existing keys, not new articles.

---

## 5. Quality

### 5.1 Mechanics

| item | finding |
|---|---|
| Front matter | all 14 files carry `title`, `description`, `position`, `tags`, `seo_description`; none carries `seo_title`. `seo_description` lengths 110–157 characters, inside the audit's 50–160 band. |
| Rendered `<title>` | the portal appends a 29-character suffix the audit never counts (`01-current-system.md` §8). `commerce-store-needs-reconnecting` EN is 34 + 29 = **63 > 60**; `commerce-store-unreachable` is exactly 60. The other five EN titles are 58–59. |
| Titles | hub and support are in the reader's words ("When something is not working", "Raising a ticket with Lynomia"). The commerce five name a *cause* ("Your store keys cannot do that", "Lynomia cannot reach your store"), which is findable only by a reader who has already diagnosed. |
| Description voice | hub and support: "You will be able to…" / "How to reach…". Commerce five: noun phrases ("What … means, why … and the one action…"). The corpus convention elsewhere is the "You will…" reader outcome (`audit-logs`, `webhooks`, `whatsapp-nothing-arrives`). |
| Tags | `[troubleshooting]` ×2, `[troubleshooting, commerce]` ×5. Consistent. |
| Internal links | hub 27, support 11, **commerce five 0**. The five make seven references by bold title instead (`reconnecting:54`, `unreachable:35`, `keys:50-51` ×2, `address:50-51` ×2, `action:43`), which a reader cannot click. |
| Role and place | only `reconnecting:12` says who can act. The hub and support have a role section; the other four commerce articles are silent although the whole Settings → Commerce route is administrator-only (`commerce.routes.js:19`). |
| Worked example | none of the seven. (`whatsapp-error-131049` and `whatsapp-nothing-arrives` each have one.) |
| Escalation | none of the five commerce articles links to the ticket article or says what to send; the hub says "escalating" (hub 79) with no link. `contact-lynomia-support` has **0** inbound links from the corpus. |
| Media | none. There is no media system (`01-current-system.md` §9.8). The three images that would pay for themselves: the stale banner, a store row with its buttons per platform, and the unknown-outcome result. |
| Length | support 1000 words is the longest; the commerce five are 404–601, which is right for one remedy each. |

### 5.2 The shape of a troubleshooting article here

What the good moments do, and where they are:

1. **Route before explaining.** The hub's second table gives symptom → first thing to check → article, in the
   reader's words, one check per row (`troubleshooting.md:30-46`). It is the right unit; it only lacks the commerce
   rows and the ticket link.
2. **Say what the product already did.** `unreachable:16-27` — bounded waits, one read retry, the stale fallback,
   the status left alone. This is the most useful kind of sentence in a troubleshooting article because it tells the
   reader what *not* to do (do not retry, nothing to clear). Nothing else in the section does it.
3. **Name the unknown and the way out.** `action:26-42`: Lynomia cannot tell, here is what it does to find out,
   here is what it never does, here is the authoritative place to look (the store's own admin, "a few seconds").
   The only comparable moments in the wider corpus are `whatsapp-error-131049` "Limits" ("Lynomia Chat cannot tell
   you how close a contact is to the cap. Meta does not report that") and `whatsapp-nothing-arrives` "What an
   operator can check that you cannot".
4. **Use the product's own sentences.** The support article is word-for-word the shipped statuses, hints and menu
   path (S2, S4, S7) and the Arabic matches the Arabic locale (`ar/platformSupport.json`). It is the only article in
   the section a reader can match to their screen — and the only one of the seven that never needed a correction in
   that respect.
5. **Distinguish the neighbour.** The "What this is not" endings (`keys:48-51`, `address:47-51`,
   `reconnecting:50-54`) are the right move; they need real links.
6. **Say how it ends.** `unreachable:42-45` "When it clears up" is the only "how you know it worked" in the section.

What the section does wrong, as a pattern rather than a list:

- **Diagnosis before symptom.** Four of five commerce articles open by classifying the problem ("This is a
  *connection* problem, not an authorization one", "A store in this state has stopped working completely", "This
  one is refused *before any request leaves Lynomia*"). The reader has not yet confirmed they are in that state.
  The "What you see" table that should come first comes second, and its left column is invented (§3.2).
- **Identifiers the reader never sees.** The right-hand "The code behind it" column prints `AUTH_INVALID`,
  `PERMISSION_DENIED`, `read_only_key`. The product renders sentences, never codes (`useCommerceLabels.js:54-89`).
  Codes are useful to the *desk*, not the reader; presenting them as the reader's anchor makes the table look like
  evidence and match nothing.
- **Causes written as facts.** §3.4. The cause tables read as if Lynomia observed the cause.
- **One remedy for four platforms.** The reconnect article is the clearest case (R2): the generalisation was
  written from the Zid/Shopify path and then stated for all four.
- **No end.** No "how you know it worked" in four of five; no escalation in five of five.

### 5.3 What Lynomia knows versus what it guesses

Do the articles tell the reader which is which? **No — and in a few places they say the opposite of what the code
knows.** The code distinguishes three classes and the corpus has no vocabulary for the distinction:

| class | examples in this section | how the corpus should phrase it |
|---|---|---|
| **Recorded** — Lynomia received or wrote it | an HTTP status class; "the store did not answer within 8 s"; the `needs_reauth` flag; "nothing was sent"; the last error code and count on the store | plain statement: "Lynomia recorded…", "Lynomia received…" |
| **Inferred** — Lynomia concluded it from a recorded fact | `REFUND_DECLINED` from one WooCommerce error code; "not approved" from Shopify's message wording (`shopify/graphql.rb:60-65`); `read_only_key` from a refused webhook registration (`woocommerce.rb:100-107`); `NOT_APPLIED` from a read-back; a Zid scope gap from a 403 | "Lynomia concluded…", with the basis, and "usually"/"can" for any cause |
| **Provider-side** — only the provider or the host knows | the key was deleted; the app was uninstalled; the gateway's reason; whether the host throttles; whether Meta redelivers | never in the indicative; always paired with where the reader can look ("in WordPress → WooCommerce → Settings → Advanced → REST API, see whether the key still exists") |

Two structural facts make the discipline necessary rather than stylistic. Lynomia **never keeps the provider's own
error text** (`action_result.rb:6`; `http_client.rb:13`), so a sentence that paraphrases the store's reason cannot
have come from Lynomia's data. And Lynomia's recorded snapshot **goes stale against the provider**: it learns
`read_only_key` once and keeps it until the keys are re-entered (`woocommerce.rb:94-108`), so a merchant who raises
the permission in WooCommerce and does nothing in Lynomia stays "read-only" — the step "Replace keys" is needed
even when the provider side is already fixed, and the article does not say so.

### 5.4 Proposed canonical troubleshooting-article pattern

Scope: an article a reader reaches **from a symptom** — a banner, a failed message, a status chip, a refused action.
It covers symptom articles and class-of-remedy articles (the commerce five). Meta code articles (agent 054's
section) are a specialisation of the same pattern with two extra elements (the code, and who decides); I have not
reconciled with 054 because its report was still incomplete when I read it.

**Front matter**

- `title` — the symptom in the product's own words, or the chip or banner text, never a cause and never a code.
  *Reason:* the reader arrives with a string; portal search matches text; the section's own titles are only
  findable by a reader who has already diagnosed.
- `description` — "You will know…" reader-outcome sentence, naming the one thing they will be able to do.
  *Reason:* the convention in the better articles; the five commerce articles are the outliers.
- `tags` — `[troubleshooting, <area>]`. `seo_description` carries the quoted sentence, not the code.

**Body — elements in order.** Elements 1, 3, 5, 6 and 8 are mandatory; 2, 4, 7, 9, 10 are included where they
apply.

| # | element | what it is | reason |
|---|---|---|---|
| 1 | **What you see** | the shipped sentence(s), verbatim, in quotes; the surface and route where they appear; the role that sees them | symptom first; and checkable — each quote must exist in the locale file for that language |
| 2 | **What Lynomia already did** | automatic behaviour: retries, fallbacks, status left alone, nothing sent, no money moved | tells the reader what not to do; the strongest sentence in `unreachable` and the shipped "Nothing was sent." |
| 3 | **What Lynomia knows, and what it cannot tell you** | two short lists. Known: what was recorded or received. Cannot tell: what only the provider or host knows. Each "cannot tell" ends with where the reader can find out | separates evidence from inference (§5.3); this is `131049` "Limits" promoted to a mandatory section and moved up |
| 4 | **Likely causes** | only when more than one; each tagged *recorded* or *possible*; ordered by how often; each *possible* cause carries its check | stops the reconnect-article failure of stating inferred causes as fact |
| 5 | **What to do** | numbered steps, one action each, using the exact button label; **a table by platform whenever the remedy differs**; the role that can do it | the reconnect article's generalisation (R2) is exactly the failure this prevents |
| 6 | **How you know it worked** | the state that should change; what needs *no* action | `unreachable:42-45` is the model; four of five lack it |
| 7 | **What this is not** | the neighbouring symptom and a **link** to its article | the endings already exist; make them links |
| 8 | **If it did not work** | link to the ticket article; the facts to quote (store name, platform, time, the shipped sentence, the order number); one line on what the desk can see (the store's last recorded error and how many in a row) | none of the five has it; the desk *can* see the snapshot (`operations/account.html.erb:192-197`) and nothing says so |
| 9 | **A worked example** | three sentences with real-looking values | present in the best WhatsApp articles; absent in all seven here |
| 10 | **Related** | links only | convention |

**Rules a reviewer, or a lint, can apply** (each is mechanically checkable, so 092/097 can automate them):

1. Every quoted on-screen string must match a shipped string in the same language's locale file (`rg -F` over
   `app/javascript/dashboard/i18n/locale/<loc>/` and `config/locales/<loc>.yml`). Arabic articles quote the Arabic
   locale, never a translation of the English article's quotes.
2. An identifier (`AUTH_INVALID`, `read_only_key`) appears only in a block marked "visible to Lynomia support, not
   on your screen", or not at all.
3. A causal sentence about a provider, store or host is never indicative unless it is *recorded*; "usually" and
   "can" are required otherwise; no past-tense claim about what a provider did unless the product received it.
4. Every registry code mapped to the article (`documentationLinks.js:108-133`) appears in it, and an article is not
   registered for a code it does not explain.
5. A remedy that differs by platform is a table keyed by platform, with the exact button label.
6. Cross-references are links, never bold titles.
7. Side effects are stated as the product states them ("Nothing was sent.", "No money was sent.").
8. No promise on Lynomia's behalf without a mechanism behind it (S9).
9. A setting only an operator can change (an environment variable) is not offered as something the reader does.
10. The article states the role, and whether the page exists at all on this plan.

**A compact illustration** — the reconnect article, rewritten to the pattern (the facts are the ones in §3.3):

```
title:  Needs re-authorization
description: You will know why a store shows "Needs re-authorization", what Lynomia recorded, and the one action
that fixes it on your platform.

## What you see
In Settings → Commerce the store shows "Needs re-authorization". In a conversation the panel says "The store
rejected Lynomia's credentials. An administrator needs to reconnect the store."

## What Lynomia already did
It stopped asking this store for anything and cleared its cached data. Conversations, contacts and your order-action
history are untouched.

## What Lynomia knows, and what it cannot tell you
Known: your store (or its token refresh) refused Lynomia's access. Cannot tell why: a deleted key, a removed app, a
lapsed authorization or a host stripping the Authorization header look the same from here. Your own store's admin
shows which.

## What to do
| Platform | Where | Who |
| WooCommerce | Settings → Commerce → the store → Replace keys | administrator |
| Salla | update or reinstall the app from the Salla dashboard; the store reconnects on its own | administrator |
| Zid, Shopify | Settings → Commerce → the store → Reconnect | administrator |

## How you know it worked
The store shows "Active" and the panel loads orders again.

## If it did not work
Open a ticket (link) with the store name, the platform, when it started and the sentence above. Lynomia's support
can see the last error recorded for your store.
```

Two things the pattern deliberately does not require yet: screenshots (there is no media system) and any response
time for the desk (no SLA policy can be created, PD-02).

---

## 6. EN/AR parity

Structural parity is exact: same headings, same table rows, same link list in both locales for all seven (hub 27 = 27,
support 11 = 11, commerce 0 = 0), no sentence present in only one language. Meaning parity is strong. That is the
problem as much as the strength: **the Arabic faithfully reproduces every English error**, and its quoted strings are
translations of the invented English ones rather than the Arabic locale.

| # | issue | EN | AR / evidence |
|---|---|---|---|
| P1 | quoted strings | invented (§3.2) | the AR quotes («متجرك لم يُجب», «لا نعرف إن طُبِّق ذلك», …) are absent from `ar/commerce.json`; shipped e.g. STORE_UNAVAILABLE «لا يمكن الوصول إلى المتجر حاليًا.», AUTH_INVALID «رفض المتجر بيانات اعتماد {installationName}. يجب على المسؤول إعادة ربط المتجر.» |
| P2 | status term | "Needs re-authorization" | UI «يحتاج إعادة تفويض» (`ar/commerce.json` SETTINGS.STATUS.NEEDS_REAUTH); the AR article says «إعادة تصريح» in the reconnect title description, table and prose |
| P3 | product names | WooCommerce, Shopify | UI keeps them in Latin (`ar/commerce.json` PROVIDERS: "WooCommerce", "Shopify"; Salla «سلة» and Zid «زد» are localised); the articles write «ووكومرس» and «شوبيفاي». `CLAUDE.md` protects product and brand names unless an official localised form exists, and a reader searching the UI name finds nothing |
| P4 | button names | "Replace keys", "Reconnect", "Turn on order actions" | UI «استبدال المفاتيح», «إعادة الربط», «تفعيل إجراءات الطلبات»; the AR keys article says «شغّل إجراءات الطلبات» and never names «استبدال المفاتيح» (it is missing from the EN too, R2) |
| P5 | links | bare key → the EN article | every Arabic internal link renders to the **English** article: 38 links in this section (hub 27, support 11); 494 corpus-wide — blocker in `076-internal-linking.md` Defect 1, because `articles.slug` for Arabic is `<key>-ar` and the route has no locale (`config/routes.rb:519`, `articles_controller.rb:80-82`) |
| P6 | numerals | "40 minutes" | AR `unreachable` uses Arabic-Indic «٤٠», while the rest of the section uses Western digits or words («10 ميغابايت», «ثلاث ثوانٍ», `LYN-000123`) |
| P7 | status label | "Resolved" | AR «مُعالَجة» (processed) is the product's own label (`ar/platformSupport.json` ENUMS.STATUS.RESOLVED) and the article mirrors it, but the next sentence says «وإن لم تُحلّ» (solved) — two roots for one idea. Product decision for 061 |
| P8 | desk count | "two… support desks" over three rows | AR «مكتبا دعم مختلفان» over three rows (S1) |
| P9 | "three you can fix yourself" | S10 | AR repeats the self-contradiction |
| P10 | bidi hazards | `` `read_only_key` ``, REST API, → arrows inside Arabic sentences | inline Latin tokens and arrows in RTL prose (`commerce-keys-cannot-do-that` AR 16, 22-24); route to 061/072 |
| P11 | "inbox" | one word for the Inbox section and a channel | AR splits it («صندوق الوارد» / «قناة تواصل») correctly; flag for 061 that the support article's AR table uses the first for both rows it needs |

---

## 7. Not checked, unverifiable here, and open questions

- **No browser, no run.** Rendering was not observed. Arabic link targets are from route and controller reading
  (corroborated by 076). Whether a billing-locked account can *navigate* to Help & Support in the browser (S13)
  was not exercised; the API side is confirmed.
- **Provider semantics** (not Lynomia's code): WooCommerce key editing and its REST API menu path (K3), WooCommerce
  401 behaviour on an under-permissioned write (already open as item 045 in the ledger), Zid's redirect-to-login
  reason, Salla's uninstall semantics, Shopify's protected-customer-data policy, **whether Meta redelivers missed
  webhooks** (H8 — routes to 026/088).
- **Hub rows I did not verify:** campaigns' per-recipient outcomes, import skip reasons (labels, country),
  audience matching, the "fourteen event types", "an agent sees no settings at all" — owned by 051, 052, 057, 059.
- **Vendor-policy sentences:** "we never read or answer your customers' conversations" (S12); whether the desk
  reads application logs for automation (H6).
- **`wc -w` and Arabic:** other agents' AR word counts (049–062) taken with plain `wc -w` are low by ~4-5x.
- **Pattern reconciliation:** the canonical pattern in §5.4 is not yet reconciled with 054's code-article shape
  (its report was incomplete when I read it), with decision XA-01 (Meta admission rule), or with the AR
  link-rewrite decision (076 R1) it depends on for the "link, don't bold" rule to be true in Arabic.
- **XA-02** (how to document a built-but-held capability) blocks the rewrite of `commerce-keys-cannot-do-that` and
  `commerce-order-action-did-not-apply` and M3; I did not pre-empt it.
