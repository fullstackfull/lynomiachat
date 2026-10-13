---
agent: 062
scope: English corpus quality and cross-corpus information architecture across all 63 EN articles and manifest.yml
confidence: high
---

All 63 EN files and `manifest.yml` were read or measured. Every number below is reproducible from the repository
at `claude/documentation-v2`. Where a judgement is mine rather than a measurement, it says so.

## 1. Inventory

63 EN articles in 12 sections, **53,975 EN words** (mean 857, median 910, min 330, max 1,676, σ 323). AR siblings
total 44,924 words. `in`/`out` are in-degree and out-degree in the EN internal link graph (§5.6).

| key | title | pos | EN w | AR w | seo_t | in | out | verdict |
|---|---|---:|---:|---:|:-:|--:|--:|---|
| _**getting-started**_ | | | | | | | | |
| `welcome-to-lynomia-chat` | Welcome to Lynomia Chat | 10 | 479 | 388 | – | 0 | 7 | KEEP |
| `set-up-your-account` | Set up your account | 20 | 760 | 651 | – | 1 | 3 | KEEP |
| `invite-your-team` | Invite your team | 30 | 843 | 679 | – | 5 | 3 | KEEP |
| `connect-your-first-channel` | Connect your first channel | 40 | 979 | 806 | – | 4 | 5 | EXPAND |
| `your-first-conversation` | Your first conversation | 50 | 984 | 817 | – | 2 | 6 | KEEP |
| _**conversations**_ | | | | | | | | |
| `work-in-the-inbox` | Work in the inbox | 10 | 1033 | 936 | – | 11 | 7 | KEEP |
| `assign-and-prioritise` | Assign and prioritise | 20 | 947 | 826 | – | 5 | 6 | KEEP |
| `labels` | Labels | 30 | 1036 | 903 | – | 12 | 6 | KEEP |
| `canned-responses` | Canned responses | 40 | 916 | 736 | – | 4 | 4 | KEEP |
| `macros` | Macros | 50 | 1006 | 801 | – | 9 | 8 | KEEP |
| `macros-or-automation` | Macros or automation? | 60 | 1047 | 928 | – | 5 | 8 | KEEP |
| _**contacts**_ | | | | | | | | |
| `contacts` | Contacts | 10 | 1093 | 877 | – | 9 | 6 | KEEP |
| `custom-attributes` | Custom attributes | 20 | 1250 | 1016 | – | 5 | 6 | KEEP |
| `import-contacts` | Import contacts | 30 | 1401 | 1155 | – | 7 | 5 | KEEP |
| `bulk-actions` | Bulk actions on contacts | 40 | 1303 | 1053 | – | 4 | 6 | KEEP |
| _**audiences-and-campaigns**_ | | | | | | | | |
| `shared-audiences` | Shared audiences | 10 | 1535 | 1331 | – | 13 | 8 | KEEP |
| `labels-or-shared-audiences` | Labels or shared audiences? | 20 | 1262 | 1061 | – | 6 | 7 | KEEP |
| `whatsapp-campaigns` | WhatsApp campaigns | 30 | 1676 | 1394 | – | 21 | 8 | KEEP |
| _**whatsapp**_ | | | | | | | | |
| `connect-whatsapp` | Connect a WhatsApp number | 10 | 1193 | 950 | – | 11 | 4 | KEEP |
| `whatsapp-business-coexistence` | The WhatsApp Business app and Lynomia Chat on one number | 20 | 988 | 780 | – | 3 | 5 | KEEP |
| `the-whatsapp-24-hour-window` | The WhatsApp 24-hour window | 30 | 867 | 686 | – | 21 | 5 | KEEP |
| `whatsapp-templates` | WhatsApp templates | 40 | 1327 | 1108 | – | 10 | 5 | KEEP |
| `whatsapp-template-lifecycle` | The template lifecycle | 50 | 1178 | 956 | – | 8 | 4 | KEEP |
| `whatsapp-troubleshooting` | When WhatsApp does not work | 60 | 1223 | 997 | – | 16 | 19 | RELOCATE |
| _**whatsapp-errors**_ | | | | | | | | |
| `whatsapp-error-131049` | Error 131049 — WhatsApp refused the message for this one person | 10 | 529 | 433 | y | 5 | 7 | KEEP |
| `whatsapp-error-131042` | Error 131042 — the WhatsApp Business account cannot be billed | 20 | 463 | 393 | y | 3 | 4 | KEEP |
| `whatsapp-error-131053` | Error 131053 — WhatsApp could not fetch the file | 30 | 405 | 321 | y | 1 | 3 | KEEP |
| `whatsapp-error-131060` | Error 131060 — an incoming message WhatsApp will not hand over | 40 | 360 | 290 | y | 2 | 3 | KEEP |
| `whatsapp-error-190` | Error 190 — the WhatsApp access token is no longer valid | 50 | 437 | 361 | y | 3 | 5 | KEEP |
| `whatsapp-number-status` | Flagged, restricted, banned — what the number's status means | 60 | 533 | 436 | y | 4 | 6 | KEEP |
| `whatsapp-quality-and-limits` | Quality rating and messaging limits | 70 | 557 | 460 | y | 4 | 5 | KEEP |
| `whatsapp-display-name` | The display name was not approved | 80 | 330 | 264 | y | 1 | 3 | KEEP |
| `whatsapp-nothing-arrives` | Nothing is arriving from WhatsApp | 90 | 522 | 423 | y | 3 | 6 | KEEP |
| `whatsapp-reconnect-a-number` | Reconnect a WhatsApp number | 100 | 529 | 442 | y | 5 | 6 | KEEP |
| `whatsapp-number-already-connected` | \"Channel already exists for this phone number\ | 110 | 391 | 285 | y | 2 | 3 | KEEP |
| `whatsapp-contact-info-requests` | A contact information request was refused | 120 | 455 | 375 | y | 2 | 4 | KEEP |
| `whatsapp-business-scoped-contacts` | Business-scoped WhatsApp contacts, and what cannot be sent to them | 130 | 391 | 315 | y | 2 | 4 | KEEP |
| `whatsapp-find-a-failed-message` | Finding the conversations where a message failed | 140 | 571 | 463 | y | 1 | 6 | KEEP |
| _**automation**_ | | | | | | | | |
| `automation-rules` | Automation rules | 10 | 977 | 852 | – | 19 | 9 | KEEP |
| `flow-builder` | Flow builder | 20 | 1055 | 905 | – | 9 | 8 | KEEP |
| `automation-or-flow-builder` | Automation or flow builder? | 30 | 955 | 780 | – | 4 | 6 | KEEP |
| `agent-bots` | Agent bots | 40 | 1103 | 901 | – | 3 | 5 | KEEP |
| _**commerce**_ | | | | | | | | |
| `commerce-overview` | What connecting a store gives you | 10 | 912 | 769 | – | 13 | 9 | KEEP |
| `commerce-provider-support` | What each platform supports | 20 | 1036 | 985 | – | 8 | 7 | KEEP |
| `connect-woocommerce` | Connect WooCommerce | 30 | 930 | 781 | – | 2 | 3 | KEEP |
| `connect-salla` | Connect Salla | 40 | 837 | 696 | – | 2 | 3 | KEEP |
| `connect-zid` | Connect Zid | 50 | 836 | 688 | – | 2 | 3 | KEEP |
| `connect-shopify` | Connect Shopify | 60 | 846 | 713 | – | 3 | 3 | KEEP |
| `customer-360` | Customer 360 | 70 | 1092 | 971 | – | 7 | 6 | KEEP |
| _**workspace**_ | | | | | | | | |
| `set-up-an-inbox` | Set up an inbox | 10 | 853 | 826 | – | 7 | 7 | KEEP |
| `teams-and-agents` | Teams and agents | 20 | 910 | 767 | – | 5 | 7 | KEEP |
| `roles-and-permissions` | Roles and permissions | 30 | 893 | 804 | – | 24 | 4 | REWRITE |
| `your-own-help-centre` | Documentation and support | 40 | 535 | 426 | – | 1 | 5 | KEEP |
| _**integrations**_ | | | | | | | | |
| `integrations` | Integrations | 10 | 896 | 735 | – | 1 | 8 | SPLIT |
| `webhooks` | Webhooks | 20 | 1257 | 1039 | – | 2 | 6 | KEEP |
| _**administration**_ | | | | | | | | |
| `audit-logs` | Audit logs | 10 | 1017 | 816 | – | 2 | 10 | KEEP |
| _**troubleshooting**_ | | | | | | | | |
| `troubleshooting` | When something is not working | 10 | 859 | 747 | – | 4 | 16 | REWRITE |
| `contact-lynomia-support` | Raising a ticket with Lynomia | 20 | 1000 | 806 | – | 0 | 8 | KEEP |
| `commerce-store-needs-reconnecting` | Your store needs to be reconnected | 60 | 460 | 355 | – | 0 | 0 | RELOCATE |
| `commerce-store-unreachable` | Lynomia cannot reach your store | 61 | 456 | 339 | – | 1 | 0 | RELOCATE |
| `commerce-store-address-refused` | The store address was refused | 62 | 404 | 332 | – | 0 | 0 | RELOCATE |
| `commerce-keys-cannot-do-that` | Your store keys cannot do that | 63 | 456 | 359 | – | 0 | 0 | RELOCATE |
| `commerce-order-action-did-not-apply` | An order action did not apply | 64 | 601 | 436 | – | 0 | 0 | RELOCATE |

Section sizes: whatsapp-errors 14 · commerce 7 · troubleshooting 7 · conversations 6 · whatsapp 6 ·
getting-started 5 · contacts 4 · automation 4 · workspace 4 · audiences-and-campaigns 3 · integrations 2 ·
administration 1. Mean 5.25, median 5.

## 2. Per-article verdict

53 KEEP, 6 RELOCATE, 2 REWRITE, 1 EXPAND, 1 SPLIT, 0 MERGE, 0 RETIRE. The table above carries the verdict per
article; only the non-KEEP ones are argued here. **There is no MERGE verdict anywhere, and that is a measurement,
not an omission** — see §5.5.

| Article | Verdict | Reason |
|---|---|---|
| `whatsapp-troubleshooting` | RELOCATE | It is the index of the `whatsapp-errors` section, not an article of the `whatsapp` section. Out-degree 19, of which **14 are the complete membership of `whatsapp-errors`** (`whatsapp/whatsapp-troubleshooting.md:109-128`, the `## When you have a code` block). No article inside `whatsapp-errors` links to more than 7 things. Move the file to `en/whatsapp-errors/` at `position: 5`; the slug and `doc_key` do not change, so nothing breaks (§7.1). |
| `commerce-store-needs-reconnecting` | RELOCATE | One of five Commerce-error articles sitting in `troubleshooting` at positions 60–64 while the equivalent WhatsApp body of work has its own section. See §7.3. |
| `commerce-store-unreachable` | RELOCATE | Same. |
| `commerce-store-address-refused` | RELOCATE | Same. |
| `commerce-keys-cannot-do-that` | RELOCATE | Same. |
| `commerce-order-action-did-not-apply` | RELOCATE | Same. All five also need the repairs in §5.3 (missing `## Related`, bold pseudo-links, curly quotes, bare brand name) — that is a rewrite of markup and front matter, not of substance: the prose itself is among the best in the corpus. |
| `roles-and-permissions` | REWRITE | Factually wrong about the thing it exists to state, in the corpus's **most-linked article** (in-degree 24). See §3.1. |
| `troubleshooting` | REWRITE | The global router has 16 outbound links and reaches **neither the escalation article nor any of the five Commerce-error articles in its own section** (`troubleshooting/troubleshooting.md`; §5.6). Its section's total intra-section link count is 2. |
| `connect-your-first-channel` | EXPAND | Documents nine channels in one table (`getting-started/connect-your-first-channel.md:16-28`) and then documents exactly one of them. See §4.1. |
| `integrations` | SPLIT | 896 words covering ten apps, and the article concedes the problem in a heading: `## The three worth a sentence each` (`integrations/integrations.md:45`). See §4.2 for the selective split, which deliberately does not produce ten articles. |

`welcome-to-lynomia-chat` (in-degree 0) and `contact-lynomia-support` (in-degree 0) are **KEEP**: the first is the
corpus root and is reached from the portal home and from `DOC_ARTICLES.gettingStarted`; the second is fixed by
giving other articles links to it, not by changing it. `your-own-help-centre` is KEEP and is the only article in
the corpus with no `DOC_ARTICLES` entry (§5.7).

## 3. Accuracy against the product

Per-section accuracy belongs to agents 049–060. I checked the claims that cross section boundaries, because an
error in a hub propagates everywhere that links to it.

### 3.1 `roles-and-permissions` under-reports the permission list — **wrong**

The article states the list twice:

- *"These are the six options, named as the product names them"* (`workspace/roles-and-permissions.md:28`), followed
  by a six-row table.
- *"The permission list is fixed at the six entries above and cannot be extended"* (`roles-and-permissions.md:92`).

The product offers **seven**. `AVAILABLE_CUSTOM_ROLE_PERMISSIONS` is
`conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`, `contact_manage`,
`report_manage`, `commerce_order_manage`, `support_ticket_manage`
(`app/javascript/dashboard/constants/permissions.js:4-12`). The missing one is live, not vestigial:

- it is in the server's closed vocabulary (`custom/app/models/custom_role.rb:20-29`);
- it is enforced — `MANAGE_PERMISSION = 'support_ticket_manage'` (`custom/app/policies/support/ticket_policy.rb:15`);
- it has a UI label, *"Manage every support case in the account"*
  (`app/javascript/dashboard/i18n/locale/en/customRole.json:35`);
- it is **not** on the model's retired list, which contains only `knowledge_base_manage`
  (`custom_role.rb:34`) — and the article handles that retired one correctly
  (`roles-and-permissions.md:47-50`), which shows the omission is an oversight rather than a policy.

The article's `## What is not on the list` (`roles-and-permissions.md:53-57`) also says nothing about support
cases, so a reader planning a support-lead role is told, twice and emphatically, that the capability they need does
not exist. **Severity: this is the corpus's most-linked article (in-degree 24).**

### 3.2 The Commerce-error articles are accurate about an undocumented remainder — **confirmed, with a gap**

`Commerce::Error::CODES` has **31** entries (`custom/app/services/commerce/error.rb:4-10`). `COMMERCE_ERROR_ARTICLES`
maps **19** of them onto the five articles (`documentationLinks.js:109-133`). Every mapped code that the articles
enumerate matches the constant, and `commerce-order-action-did-not-apply` reproduces nine of them correctly. The
twelve unmapped codes (`NOT_FOUND`, `INVALID_QUERY`, `ENCRYPTION_NOT_CONFIGURED`, `STORE_ALREADY_CONNECTED`,
`PROVIDER_DISABLED`, `INVALID_REQUEST`, `RECOVERY_DISABLED`, `RECOVERY_COOLDOWN`, `CANNOT_REPLY`,
`INVALID_RECOVERY_URL`, `CART_NOT_ABANDONED`, `STORE_LIMIT_REACHED`) resolve to `undefined` and fall back to the
general Commerce article, which is the registry's stated and correct rule (`documentationLinks.js:143-146`).
`unverifiable` whether any of the twelve is user-reachable; that is agent 043's question, not mine.

### 3.3 Relocating a file is safe — **confirmed**

`Documentation::ContentSeeder#seed_section` globs `root/<locale>/<section-slug>/*.md` and assigns that section's
category (`custom/app/services/documentation/content_seeder.rb:47-56`). An article's slug derives from the
**filename alone** (`content_seeder.rb:85-87`), and `meta['doc_key']` likewise (`content_seeder.rb:106-112`).
Therefore moving a `.md` file between section directories re-categorises the same `Article` row, keeps its slug,
keeps its `doc_key`, and breaks neither a `DOC_ARTICLES` link nor an internal corpus link. Only `position` must be
re-set. **Renaming a key is the unsafe operation** — it creates a new row and strands the old one, because the
seeder deletes nothing (`01-current-system.md` §3). Every RELOCATE in §2 is therefore a file move plus a front
matter `position` edit, with no redirect story needed.

### 3.4 The section count in the design record is stale — **wrong**

`docs/global-documentation/06-information-architecture.md` §2 documents **eleven** sections and carries the heading
*"Why these eleven and not Chatwoot's fifteen"*. The manifest ships **twelve**. `whatsapp-errors` arrived later
(commit `4db023c4`, *"a knowledge base for the refusals this installation has actually seen"*) and the manifest
still shows the retrofit: every other section is on a stride of 10 (`position: 10` … `110`) and `whatsapp-errors`
is wedged in at `position: 55` (`custom/db/documentation/manifest.yml:57-58`). The design record was not updated.

### 3.5 The design record promises ten comparison articles; three exist — **wrong, and the corpus is right**

`06-information-architecture.md` §5 lists ten confusion pairs and states that each *"is a real article, not a
paragraph inside another one"*. Measured: three are articles (`labels-or-shared-audiences`,
`automation-or-flow-builder`, `macros-or-automation`), three are `##` sections inside a host article
(`## Agent bot or flow?`, `## Campaigns or automation?` in `whatsapp-campaigns.md:102`,
`## Customer 360 or a contact?` in `customer-360.md:27`), and four are prose only. I think the corpus made the
better call and the record is the artefact to correct: a standalone *"Visible spend or lifetime value"* article
would be ~200 words and is exactly the microscopic-article failure mode (§7.5).

## 4. Missing articles

Coverage is agent 000's register; these are the holes the **IA** creates, which is my scope.

### 4.1 Eight of nine channels have one table row

`connect-your-first-channel.md:18-28` lists nine channels: WhatsApp, Website, Email, SMS, Telegram, Line,
Facebook, Instagram, API. WhatsApp has **20 articles** (`whatsapp` 6 + `whatsapp-errors` 14) — 32% of the corpus.
The other eight have a table row each and nothing else. Measured mentions across all 63 EN files:
Messenger 1 file / 1 hit; Instagram 3 files / 5 hits; Telegram 2 / 3; "live chat" 2 / 2; widget 5 / 11.
Agents 041 and 042 are chartered to discover Facebook/Messenger and Instagram, so articles are coming and the IA
has nowhere to put them — see §7.4.

### 4.2 Ten integrations, two articles

`integrations/integrations.md:8` — *"Ten exist in the product"* — then one table row each
(`integrations.md:20-30`), then `## The three worth a sentence each` (`integrations.md:45`) giving a paragraph to
Slack, Dashboard Apps and Google Translate. Dialogflow (per-inbox, credentialled), Cloudflare RealtimeKit, OpenAI,
Linear, Notion and LeadSquared have no procedure anywhere. The user question unanswered: *"I have been told to
connect Slack / Dialogflow / a dashboard app — what do I enter and what will it do to my conversations?"*

### 4.3 Notifications have no article at all

Eight files mention a notification; **all eight are single passing mentions**, and three of them are the negative
form — *"There is no notification"* (`whatsapp-errors/whatsapp-error-131060.md:47`,
`whatsapp-errors/whatsapp-find-a-failed-message.md:65`, `whatsapp-errors/whatsapp-display-name.md:44`). The corpus
repeatedly tells a reader which notifications do **not** exist and never once says which do. Agent 034's entire
area is undocumented. The user question: *"what gets me alerted, where, and how do I turn it off?"*

### 4.4 `administration` is a one-article section, and the missing content is real

The section is named and described for its single article — *"Administration: What happened in your account, and
who did it"* (`manifest.yml:89-96`). Billing, plans, subscriptions and invoices are mentioned in 4–24 files and
have no article; they are also **not** in `06-information-architecture.md` §4's list of deliberate exclusions
(which covers Captain, Voice, Reports, widget recipes, migrations and Chatwoot's commercial terms). So they are an
unrecorded gap, not a decision. Verdict: the section is under-filled, not mis-conceived (§7.2).

### 4.5 Agent signature and composer behaviour

`signature` appears in 4 files, 12 hits, and only once in a user-facing sense — *"signature says your name"*
(`conversations/canned-responses.md:61`). Nothing explains where a signature is set or how it interacts with
WhatsApp. Agent 030's area.

## 5. Quality

### 5.1 Voice and register — consistent, and deliberately so

There is a real house voice and it holds across 63 files.

| Measure | Result |
|---|---|
| `description` opening with *"You will"* | 39 of 63; *"You will know"* 24 of 63 |
| British spelling | prioritise 11 / prioritize 0 · labelled 11 / labeled 0 · behaviour 3 / behavior 0 · cancelled 6 / canceled 0 · catalogue 8 / catalog 0 · recognise 2 / recognize 0 · centre 7 / center 0 (the one "Center" is Chatwoot's own *Help Center* product name) |
| UI paths | 64 bold arrow paths, **all** using `→`; zero use `>`. `Settings → …` 59 times |
| H1 inside a body | 0 of 63 — the title comes from front matter, with no exceptions |
| Heading depth | 519 `##`, exactly **one** `###` in the whole corpus (`troubleshooting/contact-lynomia-support.md:37`) |
| Em dash | 399 |

Two register exceptions, both small and both locatable. `authorise` 1 / `authorize` 2 — the American spellings
are inside OAuth button labels, which is correct. And the brand splits: *"Lynomia Chat"* 252 times for the
product, bare *"Lynomia"* 25 times for the vendor — legitimate in `contact-lynomia-support` (*"Lynomia itself"*,
*"a Lynomia engineer"*) but wrong in the five Commerce-error articles, where *"Lynomia cannot reach your store"*
(5 occurrences) uses the vendor name for the product.

### 5.2 Task-orientation versus feature-description — a measurable house template

There is an undeclared but strongly observed article contract. Repeated `##` headings:

| Heading | Files |
|---|---|
| `## Related` | 57 |
| `## Limits` | 52 |
| `## Who can do this` | 45 (+2 `## Who can do what`) |
| `## If it does not work` | 39 |
| `## A worked example` | 38 |
| `## What you need first` | 24 |
| `## Steps` | 24 |

This matches the contract written down in `06-information-architecture.md` §3, including its instruction to skip
inapplicable slots rather than pad them — which is why the counts differ. Task-orientation, measured honestly:
**24 of 63 articles are procedural** (they carry `## Steps`), 37 of 63 have at least one numbered step, and 26 have
none. The remaining 39 are concept, decision or symptom articles. `## What you need first` and `## Steps` both
appear 24 times but **not on the same 24 files** — six have steps with no prerequisites block and six the reverse.
That is the only inconsistency in the template and it is cosmetic.

My judgement: this corpus is **not** feature-description dressed as help. The 52 `## Limits` sections and the 39
`## If it does not work` sections are the opposite of a feature tour, and the recurring honesty (*"Meta owns these
outcomes"*, `whatsapp/whatsapp-troubleshooting.md:11`) is the register a stuck user needs. The weakness is not
orientation, it is that nothing enforces the template — it is a convention living in 63 files and one design note.

### 5.3 The five Commerce-error articles are a stylistic island

They diverge from the rest of the corpus on five independent axes at once, which identifies them as a later
authoring wave (commit `9845f604`) that was never reconciled:

| Axis | The five | The other 58 |
|---|---|---|
| Curly double quotes `“ ”` | **all 27 occurrences in the corpus** | 0 |
| `## Related` | absent from all five | present in 57 of 58 (only `welcome-to-lynomia-chat` lacks it) |
| `## Limits` / `## Who can do this` | absent from all five | 52 / 45 |
| Out-degree | **0 for all five** | mean 6.0 |
| `position` stride | 60, 61, 62, 63, 64 — stride 1 | stride 10 everywhere else, in every section |
| Brand | *"Lynomia cannot …"* for the product | *"Lynomia Chat"* |

The out-degree-0 finding has a precise cause, and it is a markup mistake rather than an authoring one: the five
articles **do** cross-reference each other, in bold instead of as links. Six such pseudo-links:

- `commerce-order-action-did-not-apply.md` → `**Your store keys cannot do that**`
- `commerce-keys-cannot-do-that.md` → `**Your store needs to be reconnected**`, `**Lynomia cannot reach your store**`
- `commerce-store-needs-reconnecting.md` → `**Your store keys cannot do that**`
- `commerce-store-address-refused.md` → `**Lynomia cannot reach your store**`
- `commerce-store-unreachable.md` → `**The store address was refused**`

Each names another article's exact `title`. The intent is there; the brackets are missing.

### 5.4 Article length — bimodal, and the corpus is telling you something

| Band (EN words) | Files |
|---|---|
| 200–399 | 4 |
| 400–599 | 16 |
| 600–799 | **2** |
| 800–999 | 19 |
| 1000–1199 | 13 |
| 1200–1399 | 6 |
| 1400–1599 | 2 |
| 1600–1799 | 1 |

Two populations with an almost empty band between them. The short mode (20 files, 330–599 words) is the 14
`whatsapp-errors` articles plus the 5 Commerce-error articles plus `welcome-to-lynomia-chat`. The long mode (38
files, 800–1,399) is every task and concept article. Per-section means make it plain: whatsapp-errors 462,
troubleshooting 605, commerce 927, conversations 997, automation 1,022, whatsapp 1,129, contacts 1,261,
audiences-and-campaigns 1,491. **The corpus already has two article types and has never named them.** That matters
for §7.5: the band to hold is 350–600 for a symptom/error article and 800–1,400 for a task or concept article, and
the empty 600–800 band is evidence that authors have been respecting the split instinctively.

**Zero images in all 63 files.** Measured: 0 `![` across the corpus. This corroborates `01-current-system.md` §9.8
and it means every one of the 24 `## Steps` sections is prose-only.

### 5.5 Duplication and overlap — low, measured, and no MERGE is warranted

6-gram shingle comparison across all 1,953 article pairs, with each `## Related` list stripped so link lists do
not inflate the score. Containment = shared shingles ÷ the smaller article's shingles.

| Pair | Containment | Jaccard |
|---|---|---|
| `connect-shopify` ↔ `connect-zid` | 0.169 | 0.092 |
| `connect-salla` ↔ `connect-zid` | 0.096 | 0.050 |
| `connect-salla` ↔ `connect-shopify` | 0.090 | 0.047 |
| `whatsapp-nothing-arrives` ↔ `whatsapp-troubleshooting` | 0.070 | 0.021 |
| `connect-your-first-channel` ↔ `connect-whatsapp` | 0.058 | 0.026 |
| `labels-or-shared-audiences` ↔ `conversations/labels` | 0.052 | 0.025 |

**Only 6 of 1,953 pairs exceed 0.05 containment, and the maximum anywhere is 0.169.** For a 63-article corpus with
a seven-slot house template, that is remarkably low: it means the template was used as a question list, not as a
copy-paste skeleton. There is nothing to merge, and any recommendation to merge the four `connect-*` articles or
fold `whatsapp-errors` into `whatsapp` would be destroying distinct prose to solve a problem that does not exist.

The one *jurisdictional* overlap worth naming is `whatsapp-troubleshooting` ↔ `whatsapp-errors`. Its
`## A number is not connected` Account Health table and its `## Limits` bullets restate, in compressed form, what
`whatsapp-nothing-arrives`, `whatsapp-reconnect-a-number`, `whatsapp-number-status`, `whatsapp-display-name` and
`whatsapp-number-already-connected` say at length. That is a legitimate router-plus-detail pattern, not
duplication — and it is the reason the article is the `whatsapp-errors` index (§2).

### 5.6 The internal cross-linking graph

Built from all 63 EN files: **349 edges over 63 nodes**, mean out-degree 5.5. 138 edges stay inside a section,
**211 cross a section boundary** — the corpus is more cross-linked than internally linked, which is what a
task-organised IA should look like.

Highest in-degree (the real hubs): `roles-and-permissions` 24 · `whatsapp-campaigns` 21 ·
`the-whatsapp-24-hour-window` 21 · `automation-rules` 19 · `whatsapp-troubleshooting` 16 · `shared-audiences` 13 ·
`commerce-overview` 13. Highest out-degree (the routers): `whatsapp-troubleshooting` 19 · `troubleshooting` 16 ·
`audit-logs` 10.

`## Related` sections specifically: 252 edges, size 3–9 (mean 4.4, median 4), **51% reciprocal** and **51%
cross-section**. Separately, 220 in-body contextual links, of which 96 are destinations the article's own
`## Related` does not repeat — bodies add reach rather than pre-announcing the footer. This is a well-maintained
graph, not an accident.

**Orphans (in-degree 0), 6 of 63:** `welcome-to-lynomia-chat`, `contact-lynomia-support`,
`commerce-keys-cannot-do-that`, `commerce-order-action-did-not-apply`, `commerce-store-address-refused`,
`commerce-store-needs-reconnecting`.

**Dead ends (out-degree 0), 5 of 63:** the five Commerce-error articles (§5.3).

**Unreachable from a section index: none.** The category page lists every published article in the category
ordered by `position` (`app/controllers/public/api/v1/portals/categories_controller.rb#load_category_articles`,
`app/views/public/api/v1/portals/categories/show.html+documentation.erb`) and the portal home renders every
visible category (`app/views/public/api/v1/portals/show.html+documentation.erb`). So every article is two clicks
from the home page by construction, and "orphan" here means *contextually* unreachable, not *navigationally*
unreachable. That distinction matters: the real damage is the five dead ends, because a reader who arrives at one
from a product error banner has **no onward path at all**, not even to `contact-lynomia-support`.

Two specific defects in the graph:

1. `troubleshooting/troubleshooting.md` — the section router, titled *"When something is not working"*, with 16
   outbound links — links to **none** of the five Commerce-error articles in its own section and **not** to
   `contact-lynomia-support`. The `troubleshooting` section has 2 intra-section edges in total, the lowest of any
   section with more than two articles.
2. `contact-lynomia-support` has in-degree 0 and out-degree 8. The escalation endpoint of the entire corpus is the
   one article no other article points at — and it is the *only* article that links to `commerce-store-unreachable`,
   so the Commerce-error cluster hangs off an orphan.

### 5.7 Front matter completeness and SEO field quality

| Key | Present (of 63) |
|---|---|
| `title` | 63 |
| `description` | 63 |
| `position` | 63 |
| `tags` | 63 |
| `seo_description` | 63 |
| `seo_title` | **14** |
| `version` | 0 |
| `release_date` | 0 |

**The SEO fields pass the audit cleanly, and that is not luck.** Against `lynomia:docs:seo_audit`'s thresholds
(`01-current-system.md` §8): effective `meta['title']` over 60 chars — **0 of 63**; effective
`meta['description']` outside 50–160 chars — **0 of 63** (measured min 89, max 157, mean 133, median 134). The
reason is a real but undocumented convention: `seo_title` is supplied on exactly the 14 `whatsapp-errors` articles,
and the **only four raw titles in the corpus that exceed 60 characters are all inside that set** (66, 63, 62, 61
chars). So the escape hatch is used precisely where it is needed. The risk is that nothing enforces it: the audit
emits a *warning*, not an error, for a long title, so the first author outside `whatsapp-errors` who writes a
65-character title ships a truncated search result and a green deploy.

`description` (the card blurb, a different field from `meta['description']`) is 74–198 chars, mean 132. Two exceed
160: `integrations/webhooks.md` at 198 and `contacts/import-contacts.md` at 164. The webhooks blurb is three
chained *"you will"* clauses and reads as a run-on on a card.

### 5.8 `position` ordering sanity

Positions are unique within every section, and ascending. Two findings.

**The stride is 10 everywhere except one cluster.** That stride is not a style preference — it is the product's own
convention: `Article#update_article_position_in_category` assigns `max_position + 10`
(`app/models/article.rb:206-227`) and `Article.resequence_category` rewrites a category to `(index + 1) * 10`
(`app/models/article.rb:175-181`). The five Commerce-error articles at 60–64 (stride 1) therefore sit on a
collision course: if an operator ever reorders that category in Super Admin, the rebalance rewrites them to
30/40/50/60/70, and the next `rails documentation:content` run pushes the file values back
(`content_seeder.rb:100`). Normalise them to multiples of 10 when they are relocated.

**One ordering is substantively wrong.** In `whatsapp-errors`, `whatsapp-find-a-failed-message` ("Finding the
conversations where a message failed") is at `position: 140` — dead last of 14. It is the prerequisite for every
other article in the section: you cannot read about a code before you have found the message carrying it. It also
has the joint-lowest in-degree in the section (1). It belongs near the top. The rest of that section's order is
defensible but code-first by accident: five coded errors occupy 10–50 while the far more common uncoded symptoms
(*nothing is arriving*, 90) sit behind a display-name refusal (80).

`manifest.yml` section positions: 10, 20, 30, 40, 50, **55**, 60, 70, 80, 90, 100, 110 — the 55 is the
`whatsapp-errors` retrofit (§3.4).

### 5.9 Tag vocabulary — ad-hoc, user-visible, and navigable nowhere

**32 distinct tags over 63 files**, 1–3 per file (20 files have 1, 24 have 2, 19 have 3).

| Problem | Evidence |
|---|---|
| **Half the vocabulary is singletons** | 15 of 32 tags appear exactly once: `zid`, `woocommerce`, `webhooks`, `teams`, `support`, `shopify`, `salla`, `roles`, `quality`, `labels`, `documentation`, `delivery`, `billing`, `audit`, `attachments`, `administration` |
| **A singular/plural collision** | `inbox` (3 files) and `inboxes` (3 files) are both in use as separate tags |
| **Nine tags only restate the section** | `whatsapp`, `commerce`, `contacts`, `conversations`, `automation`, `workspace`, `integrations`, `troubleshooting`, `getting-started` are section slugs re-asserted as tags, adding no facet |
| **`errors` and `troubleshooting` overlap** | 14 and 8 files, same axis, no stated rule for which to use |

Worse, the vocabulary is **rendered to readers and does nothing**:

1. Every article header renders the tag chips unconditionally
   (`app/views/public/api/v1/portals/documentation_layout/articles/_header.html.erb:14` →
   `_release_meta.html.erb:9,22-26`). The partial's own comment declares the opposite intent — *"Shown only when it
   has them, so a documentation guide renders exactly as before"* (`_release_meta.html.erb:2-3`) — written on the
   assumption that documentation articles carry no `version`/`release_date`/`tags`. All 63 carry `tags`, so
   `tags.any?` is true and the row renders on all 126 articles.
2. **The AR articles render the English tokens.** AR front matter carries the identical tag arrays
   (e.g. `tags: [whatsapp, errors, connection]` in `ar/whatsapp-errors/whatsapp-error-190.md:5`), so an Arabic
   reader sees `whatsapp · errors · connection` in Latin script under an Arabic title.
3. **The chips are `<span>`, not links, and there is no tag route or tag index anywhere** in `config/routes.rb` or
   `config/routes/documentation.rb`. A reader cannot act on them.
4. The only other emission is `<meta name="tags" content="…">`
   (`documentation_layout/articles/_meta_head.html.erb:30-31`). `name="tags"` is not a meta tag any major search
   engine consumes, so the vocabulary carries no SEO weight either.

So the answer to "controlled or ad-hoc?" is: **ad-hoc, and currently a net liability** — decorative untranslated
chips on 126 pages. Either make it a controlled facet with an index, or stop rendering it. Choosing is agents
076/077's call; recording that it is currently neither is mine.

## 6. EN/AR parity

Structural parity is near-perfect and deserves to be said plainly, because it constrains what the program may
change. Measured across all 63 pairs:

| Check | Result |
|---|---|
| Keys present in both locales | 63 / 63, no EN-only or AR-only file |
| Section placement identical | 63 / 63 |
| `position` identical | 63 / 63 |
| `tags` identical | 63 / 63 |
| `seo_title` presence identical | 63 / 63 |
| `seo_description` presence identical | 63 / 63 |
| `##` heading count identical | 61 / 63 — AR has one extra `##` in `whatsapp-template-lifecycle` (10 vs 9) and `whatsapp-templates` (12 vs 11) |
| AR / EN word ratio | mean 0.83, range 0.73–0.97 |

The ratio is consistent with Arabic's morphology rather than with abridgement; the three lowest
(`commerce-order-action-did-not-apply` 0.73, `whatsapp-number-already-connected` 0.73, `commerce-store-unreachable`
0.74) are worth agent 061's eye but are not outliers. Semantic parity is agent 061's and agent 094's scope and I
did not assess it.

**One cross-corpus defect, and it is serious.** Every internal link in the corpus is a bare relative slug —
`[The WhatsApp 24-hour window](the-whatsapp-24-hour-window)`. In EN that resolves correctly: the article URL is
`hc/:slug/articles/:article_slug` (`config/routes.rb:519`), so a relative target lands on the sibling article. But
the AR article's own slug is `<key>-ar` (`content_seeder.rb:85-87`), and **all 494 AR internal links point at the
unsuffixed key**:

```
AR total markdown links: 494   resolving to an article key: 494   carrying the -ar suffix: 0
```

There is no link rewriting in the render path — `ChatwootMarkdownRenderer#render_article` renders CommonMark with
the `:table` extension and nothing else (`lib/chatwoot_markdown_renderer.rb:14-21`), and `CustomMarkdownRenderer#link`
only intercepts embeds (`lib/custom_markdown_renderer.rb`). So **every internal link an Arabic reader clicks
delivers the English article.** 494 links, 63 files, both the `## Related` footers and the in-body references.

The fix is not to suffix 494 AR targets — that would be unmaintainable and would break if the suffix convention
changed. The locale-correct address already exists: `/docs/:article_slug` resolves the *key* through
`Documentation::Library.article_for(key, locale:)` and redirects to the reader's own language, falling back to
English (`custom/app/controllers/documentation_controller.rb:18-26`, `library.rb:54-57`). Authoring internal links
as `/docs/<key>` in **both** locales makes one spelling correct everywhere and removes the suffix from the
authoring surface entirely. That is a Phase 4 contract decision, not a corpus edit, so I am recording it rather
than specifying it.

## 7. Information architecture recommendation

The default is to preserve the twelve. I am recommending that **ten of the twelve stay exactly as they are**, that
two change by moving files rather than by restructuring, and that **one new top-level section be created, under a
stated trigger condition**. Every argument below is from a measurement in §1–§6.

### 7.1 Stay as they are — eight sections, no change

`getting-started` · `conversations` · `contacts` · `audiences-and-campaigns` · `whatsapp` · `whatsapp-errors` ·
`automation` · `workspace`.

The evidence that these are right: 211 of 349 link edges cross a section boundary, 51% of `## Related` edges cross
one, and no pair of articles anywhere exceeds 0.169 6-gram containment. A section scheme that was cutting the
wrong way would show up as either high duplication (the same thing explained twice on two sides of a boundary) or
as isolated sections. Neither is present. `whatsapp-errors` in particular is the **best-connected section in the
corpus** — 24 intra-section edges and 34 outward `## Related` edges from 14 articles — which settles the obvious
question of whether a 14-article error section is a ghetto. It is not.

`whatsapp` keeps its six articles and loses `whatsapp-troubleshooting` to `whatsapp-errors`, where that article's
19 outbound links already live. `whatsapp-errors` gains it as `position: 5` and moves
`whatsapp-find-a-failed-message` from 140 to 10 (§5.8). Both are file moves and `position` edits; §3.3 proves
nothing breaks.

### 7.2 Stay, but under-filled — two sections

`integrations` (2 articles, 10 products) and `administration` (1 article). Neither section is wrong; both are
empty. `administration`'s name and description were written to fit its single article (§4.4), and the content that
belongs there — billing, plans, invoices, the super-admin operations surface — is an *unrecorded* gap rather than a
recorded exclusion. **Do not merge `administration` into `workspace`.** `workspace`'s declared scope is "Inboxes,
teams, and who can do what"; the audit trail and billing answer "what happened and who paid", which is a different
reader (an owner, not an admin configuring access). Merging would hide the gap instead of filling it.

`integrations` takes the SPLIT from §2, selectively: an index article plus a procedure for **Slack** (two modes
with different safety consequences), **Dashboard Apps** (an iframe contract with a documented payload) and
**Dialogflow** (per-inbox, credentialled, and it answers customers). The other six stay as catalogue rows with a
sentence, because a key-and-a-switch integration does not earn an article. That is three new articles, not ten —
and the article itself already made this judgement under the heading `## The three worth a sentence each`
(`integrations.md:45`); the recommendation is to promote its own three, with Dialogflow in place of Google
Translate on the grounds that Dialogflow has a setup procedure and Google Translate has none.

### 7.3 Change by relocation — two sections, zero new sections

`troubleshooting` loses its five Commerce-error articles to `commerce`. The argument is an asymmetry, and it is
measurable rather than aesthetic:

| | WhatsApp errors | Commerce errors |
|---|---|---|
| Articles | 14 | 5 |
| Mean EN words | 462 | 528 |
| Reached from the product by code | yes (`whatsappErrorArticle`) | yes (`commerceErrorArticle`, 19 codes → 5) |
| Section | **its own** (`whatsapp-errors`) | inside the generic `troubleshooting` |
| Intra-section link edges | 24 | **0** |
| `## Related` present | 14 / 14 | **0 / 5** |

The same content pattern — a per-provider error knowledge base reached by deep link from the failure — got a
section for WhatsApp and a corner of `troubleshooting` for Commerce. The corner is where the wiring rotted: five
dead ends, four orphans, six bold pseudo-links, a stride-1 position block and the corpus's only curly quotes
(§5.3). They belong next to the four `connect-*` articles and `commerce-provider-support`, because the Commerce
error remedies are *per-platform* ("what to change — per platform", `commerce-keys-cannot-do-that.md:3`) and so is
everything else in `commerce`. `commerce` becomes 12 articles, ordered overview → provider support → four
`connect-*` → `customer-360` → five error articles.

`troubleshooting` then becomes what its name and its router already are: three articles, a cross-cutting
first-stop (`troubleshooting`), an escalation path (`contact-lynomia-support`), and no provider content. Its
router must then link to the escalation article and to each provider's error cluster — which fixes the §5.6
defects as a side effect rather than as a separate task.

**I explicitly reject creating a `commerce-errors` section** to mirror `whatsapp-errors`. The precedent is the
problem: agents 001–028 are chartered across WhatsApp Cloud API, Graph API, Messenger and Instagram Messaging, so
the symmetric move produces `messenger-errors`, `instagram-errors` and `graph-errors` — five or six sections of
three to eight articles each. That is the microscopic failure mode promoted to the section level, and it would put
provider plumbing at the top of a portal whose other ten sections are about what a user is trying to do. One
section earns the exception because it is 14 articles and the fastest-growing part of the corpus; five do not.

### 7.4 One new top-level section is justified — `channels`, under a trigger

This is the only addition I argue for, and I argue it conditionally.

The evidence: nine channels exist in the product (`connect-your-first-channel.md:18-28`); WhatsApp has 20 of the
63 articles; the other eight have one table row each and a measured 1–11 mentions corpus-wide (§4.1). Agents 041
and 042 are chartered to discover Facebook/Messenger and Instagram, so articles are coming. The IA has no home for
them:

- `workspace` is declared as "Inboxes, teams, and who can do what" (`manifest.yml:81-88`). Adding eight
  per-channel connection guides takes it from 4 articles to 12 and makes it two unrelated sections wearing one
  name.
- `integrations` is declared as "Connecting Lynomia Chat to the rest of your tools" — but the corpus itself
  defines a channel as an inbox, not an integration (*"In the dashboard a channel appears as an inbox: the two
  words describe the same thing from different sides"*, `connect-your-first-channel.md:9-12`), and
  `integrations.md:11-13` explicitly pushes store and bot content out of the integrations page. Channels would
  contradict that article's own boundary.
- `getting-started` is a five-step first-hour sequence; eight channel procedures would destroy it.

So: **create `channels` when the fourth non-WhatsApp channel article exists.** Until then the first two or three
live in `workspace` beside `set-up-an-inbox`. Making the section early, empty, is how a portal ends up with a
one-article section — which is exactly the state `administration` is in (§7.2) and the mistake not to repeat.
WhatsApp stays separate under its own name, because `06-information-architecture.md` §2 is right that it is the
product's centre of gravity, and because 20 articles would swamp any shared section.

Resulting shape: **13 sections** — getting-started, conversations, contacts, audiences-and-campaigns, channels,
whatsapp, whatsapp-errors, automation, commerce, workspace, integrations, administration, troubleshooting. Twelve
until the trigger fires.

### 7.5 Both failure modes, rejected from evidence in this repository

**Hundreds of microscopic articles — rejected.** The repository has already decided this and the decision is
measurably right. `commerceErrorArticle` maps 19 of 31 `Commerce::Error::CODES` onto five articles *grouped by
remedy*, with the reasoning written at the call site: *"a reader with a failed refund wants the fourth of those,
not an article about `REFUND_DECLINED` specifically"* (`documentationLinks.js:135-146`). `whatsappErrorArticle`
resolves only codes with an article, and only five coded articles exist because those are the five
`custom/app/services/whatsapp/delivery_failure.rb` classifies. Per-code articles would also be mechanically
visible as duplication: the highest 6-gram containment in the entire corpus is between the two most similar
sibling articles (`connect-shopify` ↔ `connect-zid`, 0.169) — one article per code across Meta's error surface
would make that the *typical* figure rather than the maximum. And §3.5 shows the corpus already declined to split
seven promised comparison articles into standalone pages, correctly.

**One massive article per area — rejected.** The repository shows what this looks like twice.
`integrations/integrations.md` is 896 words for ten products and has to concede `## The three worth a sentence
each` (`integrations.md:45`), leaving seven integrations with a table row. `connect-your-first-channel.md` is 979
words for nine channels and documents one. Conversely `whatsapp/whatsapp-troubleshooting.md` is the longest
troubleshooting article in the corpus (1,260 words) and works *only because* it routes to 14 separate articles
rather than containing them (`whatsapp-troubleshooting.md:109-128`).

**What the measurements say to hold instead.** The length distribution is bimodal with an almost empty 600–800
band (§5.4), and the de facto house template (§5.2) differentiates cleanly along the same line. Name the two types
and hold the bands:

| Type | Band | Required slots | Count today |
|---|---|---|---|
| Symptom / error | 350–600 EN words | `## Who can do this`, `## Limits`, `## Related` | 20 |
| Task / concept | 800–1,400 EN words | `## What you need first` + `## Steps` (task) or a decision frame (concept), then `## Who can do this`, `## Limits`, `## If it does not work`, `## Related` | 38 |

An article drifting under 350 should be a section of its neighbour; one over 1,700 should be split into a router
and its detail, which is what `whatsapp-troubleshooting` already demonstrates. The one article currently above
1,600 is `whatsapp-campaigns` (1,676). Making the template explicit — it is currently a convention in 63 files and
one design note — is the single highest-leverage quality change available, because it is what the authoring surface
(agents 063–072) can then validate.

### 7.6 Summary of the recommendation

| Section | Recommendation |
|---|---|
| getting-started | **stays**; `connect-your-first-channel` EXPAND once `channels` exists |
| conversations | **stays**, unchanged |
| contacts | **stays**, unchanged |
| audiences-and-campaigns | **stays**, unchanged |
| whatsapp | **stays**; `whatsapp-troubleshooting` relocates out to `whatsapp-errors` |
| whatsapp-errors | **stays**; gains the index article, re-orders `whatsapp-find-a-failed-message` to the front |
| automation | **stays**, unchanged |
| commerce | **stays**; gains the five Commerce-error articles (7 → 12) |
| workspace | **stays**; `roles-and-permissions` REWRITE (§3.1); temporary home for the first channel articles |
| integrations | **stays**, under-filled; SPLIT into index + Slack + Dashboard Apps + Dialogflow |
| administration | **stays**, under-filled; do not merge |
| troubleshooting | **stays**, narrowed to router + escalation; router REWRITE |
| **channels** (new) | **create on trigger**: the fourth non-WhatsApp channel article |
| ~~commerce-errors~~ | **rejected** (§7.3) |
| ~~per-provider error sections~~ | **rejected** (§7.3) |

## 8. Contradictions for the orchestrator

1. **`DOC_ARTICLES` key count — already resolved upstream, and my independent count agrees.** I measured 62
   `key: 'slug'` entries over `app/javascript/dashboard/helper/documentationLinks.js:11-94`, mapping to 62 distinct
   slugs — one per corpus article except `your-own-help-centre`. `01-current-system.md` originally said 87; while
   this report was being written it was corrected to **62 keys**, crediting agent 076's challenge
   (`01-current-system.md:226-227`). Nothing further is needed; recorded here because every reachability figure in
   §5.7 and §7 is computed against 62.
2. **`documentationLinks.js:139` says "Thirty codes"; `Commerce::Error::CODES` has 31**
   (`custom/app/services/commerce/error.rb:4-10`). Cosmetic, but it is a count in a comment that justifies a design
   decision.
3. **`docs/global-documentation/06-information-architecture.md` §2 documents eleven sections; twelve ship.** Phase 3
   reassesses IA against this record, so the record needs correcting first (§3.4).
4. **The same record §5 promises ten standalone comparison articles; three exist** (§3.5). I argue the corpus is
   right and the record should be amended rather than the corpus expanded — but that is Agent 000's call, and it
   sets the precedent for how many comparison articles Phase 5 writes.
5. **`roles-and-permissions` omits `support_ticket_manage`** (§3.1). The baseline HEAD is described in the charter
   as containing the merged Platform Support Desk; the desk's permission, its policy and its UI label all exist, and
   the corpus's most-linked article says the list is fixed at six. Whoever owns the Platform Support Desk
   documentation (agent 048) and whoever owns `workspace` (agent 057) both touch this, and they must not both edit
   the same file.
6. **The AR relative-link defect (494 links, §6) crosses my scope, agent 061's and agents 073–079's.** It is a
   single authoring-convention decision (`/docs/<key>` versus a bare slug) that belongs in the Phase 4 contract
   freeze, not in three independent reports.

## 9. Not checked

- **Semantic** EN/AR equivalence (agent 061, agent 094). I measured structure only.
- Per-article factual accuracy outside §3 (agents 049–060).
- Rendered output. I read the ERB templates and the renderers; I did not run the portal, so claims about what a
  page *looks* like are inferred from the templates and cited as such.
- Search relevance, sitemap, canonical/hreflang behaviour (agents 073–080). The tag findings in §5.9 stop at what
  the templates emit.
- Whether any of the 12 unmapped `Commerce::Error` codes is user-reachable (agent 043).
