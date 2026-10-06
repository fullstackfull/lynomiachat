# 04 — The Karzoun reference map

What an Arabic-first product in this market explains, in what order, and in which words. Karzoun Chat
(<https://karzoun.chat/>) is the closest comparable: Arabic-facing, Gulf-focused, and built on the same upstream.

Used for **what to explain and how to say it in Arabic** — never for its text.

---

## 1. The copyright position

Two statements, neither granting any reuse:

> "جميع الحقوق محفوظة ©2023" — site-wide footer

and, from <https://karzoun.chat/terms-of-service/> §3, an intellectual-property clause reserving ownership of the
site and its content.

So the rule is the same as for Chatwoot: **no sentence is reused.** What is taken is which questions an Arabic
audience asks, the order they ask them in, and the Arabic words this market actually uses.

## 2. How the inventory was obtained, and its one caveat

Every live path under `karzoun.chat/docs/` sits behind a bot challenge (HTTP 202 with a refresh stub), so the corpus
was reconstructed from Wayback snapshots (Mar 2023, Apr–May 2023, Feb–May 2024) and checked against a live 2026
homepage, whose docs menu and footer still match. The article set is identical across the 2023 and 2024 crawls.

**Treat this inventory as current but archive-sourced.** Nothing in the Lynomia corpus depends on a fact that could
only have come from it; the terminology was independently cross-checked against Lynomia's own Arabic locale files
(§4), which are authoritative.

The help centre is a WordPress/BetterDocs site branded **مكتبة الشروحات**, about **29 unique articles** in five
sections. Each article shows a view counter, which makes demand visible:

| Article | Views | What that tells us |
|---|---|---|
| ما هو حساب واتساب اعمال رسمي | 339 | *what a WhatsApp Business account is* is the single most-read page |
| طريقة فتح حساب API | 155 | how to actually open one |
| ربط حساب واتساب رسمي | 111 | how to connect it |
| الفرق بين حساب رسمي ورقم عادي | 96 | official number versus ordinary number |

**All four top articles are about WhatsApp prerequisites, not about the product.** That is the strongest single
finding in this document, and it shaped the Lynomia corpus directly: the WhatsApp section is the largest, and
[the WhatsApp 24-hour window](the-whatsapp-24-hour-window) is written for a non-technical owner rather than for an
administrator.

## 3. The onboarding order, and where Lynomia differs

Karzoun's navigation steers a new reader at **Meta prerequisites first** — what a WABA is, official number versus
ordinary number, what a template is — and only then at the product. Inside its getting-started section, **agents are
invited before any channel is connected**.

Lynomia keeps two of those decisions and changes one:

| | Karzoun | Lynomia | Why |
|---|---|---|---|
| WhatsApp prerequisites early | yes, before the product | yes, but as its own section a reader arrives at when they need it | a reader who has not yet seen the inbox has no hook to hang it on |
| Invite the team before connecting a channel | yes | **yes** | correct: the people are the point, and per-channel access is granted afterwards |
| Organised by product object | yes (labels, teams, macros) | **no — by what you are trying to do** | object-shaped docs leave cross-cutting tasks undocumented, which Karzoun's own set demonstrates |

## 4. Terminology — the part that mattered most

Karzoun shows what reads naturally in Arabic in this market. **Lynomia's own Arabic UI decides the word**, because a
reader must be able to find the thing on screen. Where the two agree, the choice is confirmed; where they differ,
Lynomia's UI wins.

| Concept | Karzoun | **Lynomia's own ar locale — the corpus uses this** | Note |
|---|---|---|---|
| inbox / channel | قناة التواصل | **قنوات التواصل** | agree. Both avoid صندوق الوارد for the object |
| conversation | المحادثات | **المحادثات** | agree |
| contact | جهات الاتصال | **جهات الاتصال** | agree |
| label | الوسوم *and* التصنيفات, used interchangeably | **الوسوم** | Karzoun is genuinely inconsistent here; Lynomia is not, and the corpus is not |
| agent | موظف (dominant), وكيل (occasional) | **وكيل الدعم** | they differ. The corpus uses Lynomia's word |
| team | فريق / الفرق | **الفرق** | agree |
| campaign | — (campaigns live in a sibling product) | **الحملات** | Karzoun has no equivalent to document |
| automation | الأتمتة | **الأتمتة** | agree |
| macro | الماكرو | **ماكروس** | minor; Lynomia's form is used |
| canned response | الردود الجاهزة / الردود السريعة | **الردود الجاهزة** | agree on the first form |
| WhatsApp template | قالب / قوالب | **القوالب** | agree |
| audience | — | **الجماهير / جمهور مشترك** | Lynomia-only concept |
| commerce | — | **المتجر** | Lynomia-only |
| resolved | مغلقة | — | Karzoun says *closed* where the UI says Resolved; the corpus does not repeat that mismatch |

## 5. Style techniques worth adopting, and ones to avoid

**Adopted:**

- **Dual-labelling.** Give the Arabic term with the English UI string in parentheses the first time: المحادثات المغلقة
  (Resolved). A reader scanning an English-labelled screen needs the bridge.
- **Business motive before mechanism.** Karzoun's teams article opens with *"if you have many channels and many
  agents…"* before any step. That is the right order, and it is the article contract's "when to use it".
- **Worked examples inline**, right where the reader types.

**Not adopted:**

- **Screenshot-led prose.** Most Karzoun articles are a thin band of text between annotated screenshots. Screenshots
  date badly, do not translate, and are unreadable to someone using a screen reader.
- **Delegating to the provider by link.** Karzoun's WhatsApp article is a chain of *اضغط هنا* links out to Meta. A
  reader who needed that article is the least able to follow them.
- **A congratulation at the end of every article** (تهانينا لك…). It is copy-pasted carelessly — the contacts article
  closes with the teams article's sentence.
- **Organising by product object.** See §3.
- **Masculine singular imperative throughout.** The corpus uses neutral phrasing where Arabic allows it.

## 6. What Karzoun documents that Lynomia does not, and the reverse

| Karzoun has | Lynomia | |
|---|---|---|
| WhatsApp Business API background as a top-level section | folded into the WhatsApp section | the prerequisites belong next to the connection guide |
| Reports | not documented yet | a deliberate gap, recorded in `06-information-architecture.md §4` |
| A mobile app article | mentioned only where true for this product | |
| Campaigns | **a whole section** | Karzoun's campaigns are a separate product; Lynomia's are built in |
| — | **Shared audiences** | no equivalent exists to compare against |
| — | **Commerce and Customer 360** | no equivalent |
| — | **Flow builder** | no equivalent |
| — | **Authoring and submitting WhatsApp templates** | Karzoun explains Meta's template rules; Lynomia lets you act on them |

---

## 7. The inventory


### Hub (2)

| Article | Topic |
|---|---|
| مكتبة الشروحات | Docs landing page listing the five sections with the newest articles under each |
| مكتبة الشروحات الأرشيف | Flat archive index of every article plus a WhatsApp-account explainer block |

### البدء مع كرزون شات (5)

| Article | Topic |
|---|---|
| إنشاء حساب في منصة كرزون شات | How to sign up and activate the account from the confirmation email |
| إضافة موظفين دعم خدمة العملاء | How to invite agents, set their role, and grant them per-channel access as collaborators |
| تطبيق كرزون شات على الجوال | What the mobile app does: conversation filters, mark-unread, delivery/read receipts, notifications |
| التعديل على الحساب واللغة | How to change account settings and switch the interface language |
| التعديل على الحساب الشخصي | How to change your own name, avatar, password and notification preferences |

### ربط واعداد قنوات التواصل (6)

| Article | Topic |
|---|---|
| ربط حساب واتساب اعمال رسمي مع كرزون شات | Prerequisites and steps to connect an official WhatsApp Business API number (most-read channel article) |
| ربط حساب انستغرام مع منصة كرزون شات | How to connect an Instagram account as a channel |
| ربط صفحة فيسبوك مع منصة كرزون شات | How to connect a Facebook page as a channel |
| ربط تويتر مع منصة كرزون شات | How to connect a Twitter account as a channel |
| ربط البريد الالكتروني (الإيميل) مع كرزون شات | How to route a support email address into the platform as a channel |
| ربط منصة كرزون شات مع متجرك الالكتروني | How to install the live-chat widget on your own store or website |

### الإضافات والمميزات (12)

| Article | Topic |
|---|---|
| جهات الاتصال | How the contact database fills up, cross-channel identity merging, and why an email or phone is required to save a contact |
| التقارير | Tour of the report pages: overview, conversations, CSAT, per-agent, and per-channel |
| طلب تقييم من العميل في المحادثة | How the post-resolution CSAT survey works and how to switch it on per channel |
| إنشاء ردود جاهزة (سريعة) | How to create canned responses and insert them in the composer with the '/' shortcut |
| اضافة وسوم | How to create account-level labels with colours and use them to prioritise and filter conversations |
| اضافة فريق عمل | How to create teams per channel, assign members, and enable even auto-distribution within a team |
| Conversation | Metric-by-metric glossary of the conversation report: incoming/outgoing, first response time, resolution time and count |
| نظام إسناد المحادثات | Manual versus automatic conversation assignment, who can assign, and the round-robin rule for online agents |
| المجلدات والفلترة والتحديد الجماعي | What each conversation folder contains, how to filter by status/team/channel/label, and how to act on conversations in bulk |
| الأتمتة | The event/conditions/actions model of automation rules, the supported trigger events, and how to build a rule |
| الرسالة الترحيبية ورسالة ساعات الدوام | How to set a per-channel greeting message and out-of-hours message, with the QR-WhatsApp caveat |
| الماكرو | What a macro is, a worked sales/spam example, and how to build and run one from the conversation panel |

### معلومات إضافية (4)

| Article | Topic |
|---|---|
| ما هو حساب واتساب اعمال رسمي | What a WhatsApp Business API account is: benefits, green-tick verification, drawbacks, pricing and billing mechanics (most-read article overall) |
| الفرق بين حساب واتساب رسمي و رقم واتساب عادي | Comparison of an official API account against an ordinary/Business-app WhatsApp number |
| طريقة فتح حساب واتساب اعمال رسمي API بالرقم الموحد | End-to-end Meta walkthrough for opening a WABA on a Saudi unified 9200 number or an ordinary number |
| انشاء قالب رسالة واتساب رسمي ميتا | When a template is required (24-hour window), how {{1}} variables work, approval best practices, categories and cost |

### التحديثات (2)

| Article | Topic |
|---|---|
| التحديثات الجديدة 2.9.0 كرزون شات | Release notes: knowledge base, dashboard customisation, external app panel, right-click status change, no-code widget styling |
| التحديثات الجديدة 2.13.0 كرزون شات | Release notes: unattended view, mark-as-unread, auto-offline, delivery/read receipts, voice & video call, macro button |

### غير مصنف (uncategorised) (2)

| Article | Topic |
|---|---|
| إختصارات لوحة المفاتيح | How to open the shortcut list (CMD+/ or Win+/); the shortcuts themselves are only in a screenshot |
| تطبيق كرزون شات على الجوال (duplicate under uncategorised) | Same mobile-app article reachable at a second uncategorised URL |

### صفحات المميزات (marketing feature pages) (24)

| Article | Topic |
|---|---|
| الأتمتة والرد الآلي | Marketing page for automation and auto-reply |
| المحادثة المباشرة في الموقع | Marketing page for the on-site live-chat widget |
| واجهة تحكم واحدة لكل الحسابات | Marketing page for the unified multi-channel control interface |
| تنسيق العمل وتوزيعه بين الموظفين | Marketing page for the shared inbox; the only live page that names صناديق الوارد |
| شات بوت | Marketing page for chatbots; source of the Arabic bot vocabulary |
| تطبيق للجوال اندرويد و IOS | Marketing page for the Android and iOS apps |
| التصنيفات | Labels feature page; note the nav label التصنيفات points at the الوسوم slug |
| ملاحظات خاصة | Private (internal) notes on a conversation |
| الفرق | Teams feature page |
| كتابة ملاحظات في بروفايل العملاء | Notes stored on the contact profile, distinct from conversation notes |
| ساعات العمل | Business-hours feature page |
| الردود السريعة | Canned/quick replies feature page |
| الإجرائات السريعة "Macros" | Macros feature page, marketed as quick actions |
| توزيع المحادثات الذكي للموظفين | Auto-assignment feature page |
| الأوامر الجماعية | Bulk conversation actions feature page |
| نافذة الانتقال السريع | Command-palette feature page |
| اختصارات لوحة المفاتيح | Keyboard-shortcuts feature page (mirrors the docs article) |
| احصائات مباشرة | Live statistics report page |
| تقارير عن الوسوم والتصنيفات | Label/classification reports page |
| تقارير عن المحادثات | Conversation reports page |
| تقارير عن رضى العملاء | CSAT reports page |
| تقارير عن الموظفين | Per-agent reports page |
| تقارير عن قنوات التواصل | Per-channel reports page |
| تقارير عن أقسام الموظفين | Team reports page |

### Legal (2)

| Article | Topic |
|---|---|
| سياسة الإستخدام (Terms and Conditions) | Terms of service; section 3 is the intellectual-property and reuse-restriction clause |
| سياسة الخصوصية (Privacy Policy) | Privacy policy covering data collection and processing |
