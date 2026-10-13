---
agent: 061
scope: Arabic corpus quality, terminology consistency, RTL hazards across all 63 files in custom/db/documentation/ar/
confidence: high
---

# Arabic corpus quality, terminology and RTL

Read first-hand against `claude/documentation-v2`. Every AR file was inventoried; every bolded UI label and
navigation path in the Arabic corpus was matched mechanically against `config/locales/ar.yml` and
`app/javascript/dashboard/i18n/locale/ar/*.json`; every file was scanned for bidi control characters, digit
systems, punctuation direction and quotation convention.

**The headline is not what the brief anticipated.** The Arabic corpus is genuinely authored, not machine
translated — the orthography is clean, the register is consistent, the structure is sometimes *better* than the
English, and the typographic discipline (Arabic commas, guillemets, no stray bidi marks) is deliberate. The
defects are of three kinds, in descending severity:

1. **The renderer never declares RTL.** No portal layout emits a `dir` attribute; direction is applied
   client-side by JavaScript after load. All 63 Arabic articles are *served* left-to-right.
2. **The Arabic product is 37% English, and the Arabic corpus quotes UI labels that do not exist.** The corpus
   translates on-screen strings that the Arabic dashboard shows in English, and in eleven confirmed places names a
   navigation target an Arabic reader cannot find.
3. **One authoring seam runs through the corpus.** The `troubleshooting/` commerce set and the
   `contacts/`+`conversations/` set were written in a different pass from the rest, with a different quotation
   convention, different brand-name policy and, in two places, a wrong navigation path.

---

## 1. Inventory

63 AR files, 63 EN files, exact per-section parity, identical `position` and `tags` values in every pair.
`seo_title` is present in exactly the 14 `whatsapp-errors` files and absent from the other 49, in both languages.
Word ratio is AR words ÷ EN words; Arabic fuses articles and prepositions, so 0.80–0.95 is the expected band for
a faithful translation and nothing here falls outside it.

| key | section | AR title | pos | EN words | AR words | ratio | seo_title |
|---|---|---|---|---|---|---|---|
| `audit-logs` | administration | سجلات التدقيق | 10 | 1017 | 816 | 0.80 | — |
| `labels-or-shared-audiences` | audiences-and-campaigns | الوسوم أم الجماهير المشتركة؟ | 20 | 1262 | 1061 | 0.84 | — |
| `shared-audiences` | audiences-and-campaigns | الجماهير المشتركة | 10 | 1535 | 1331 | 0.87 | — |
| `whatsapp-campaigns` | audiences-and-campaigns | حملات واتساب | 30 | 1676 | 1394 | 0.83 | — |
| `agent-bots` | automation | روبوتات وكلاء الدعم | 40 | 1103 | 901 | 0.82 | — |
| `automation-or-flow-builder` | automation | أتمتة أم منشئ تدفقات؟ | 30 | 955 | 780 | 0.82 | — |
| `automation-rules` | automation | قواعد الأتمتة | 10 | 977 | 852 | 0.87 | — |
| `flow-builder` | automation | منشئ التدفقات | 20 | 1055 | 905 | 0.86 | — |
| `commerce-overview` | commerce | ما يمنحك ربط المتجر | 10 | 912 | 769 | 0.84 | — |
| `commerce-provider-support` | commerce | ما تدعمه كل منصة | 20 | 1036 | 985 | 0.95 | — |
| `connect-salla` | commerce | ربط Salla | 40 | 837 | 696 | 0.83 | — |
| `connect-shopify` | commerce | ربط Shopify | 60 | 846 | 713 | 0.84 | — |
| `connect-woocommerce` | commerce | ربط WooCommerce | 30 | 930 | 781 | 0.84 | — |
| `connect-zid` | commerce | ربط Zid | 50 | 836 | 688 | 0.82 | — |
| `customer-360` | commerce | عرض العميل الشامل | 70 | 1092 | 971 | 0.89 | — |
| `bulk-actions` | contacts | الإجراءات الجماعية على جهات الاتصال | 40 | 1303 | 1053 | 0.81 | — |
| `contacts` | contacts | جهات الاتصال | 10 | 1093 | 877 | 0.80 | — |
| `custom-attributes` | contacts | السمات المخصصة | 20 | 1250 | 1016 | 0.81 | — |
| `import-contacts` | contacts | استيراد جهات الاتصال | 30 | 1401 | 1155 | 0.82 | — |
| `assign-and-prioritise` | conversations | الإسناد والأولوية | 20 | 947 | 826 | 0.87 | — |
| `canned-responses` | conversations | الردود الجاهزة | 40 | 916 | 736 | 0.80 | — |
| `labels` | conversations | الوسوم | 30 | 1036 | 903 | 0.87 | — |
| `macros-or-automation` | conversations | ماكروس أم أتمتة؟ | 60 | 1047 | 928 | 0.89 | — |
| `macros` | conversations | ماكروس | 50 | 1006 | 801 | 0.80 | — |
| `work-in-the-inbox` | conversations | العمل في صندوق الوارد | 10 | 1033 | 936 | 0.91 | — |
| `connect-your-first-channel` | getting-started | اربط أول قناة | 40 | 979 | 806 | 0.82 | — |
| `invite-your-team` | getting-started | ادعُ فريقك | 30 | 843 | 679 | 0.81 | — |
| `set-up-your-account` | getting-started | جهّز حسابك | 20 | 760 | 651 | 0.86 | — |
| `welcome-to-lynomia-chat` | getting-started | مرحباً بك في لينوميا تشات | 10 | 479 | 388 | 0.81 | — |
| `your-first-conversation` | getting-started | أول محادثة لك | 50 | 984 | 817 | 0.83 | — |
| `integrations` | integrations | خيارات الربط | 10 | 896 | 735 | 0.82 | — |
| `webhooks` | integrations | Webhook | 20 | 1257 | 1039 | 0.83 | — |
| `commerce-keys-cannot-do-that` | troubleshooting | مفاتيح متجرك لا تستطيع ذلك | 63 | 456 | 359 | 0.79 | — |
| `commerce-order-action-did-not-apply` | troubleshooting | إجراء طلب لم يُطبَّق | 64 | 601 | 436 | 0.73 | — |
| `commerce-store-address-refused` | troubleshooting | عنوان المتجر مرفوض | 62 | 404 | 332 | 0.82 | — |
| `commerce-store-needs-reconnecting` | troubleshooting | متجرك يحتاج إلى إعادة ربط | 60 | 460 | 355 | 0.77 | — |
| `commerce-store-unreachable` | troubleshooting | لينوميا لا تستطيع الوصول إلى متجرك | 61 | 456 | 339 | 0.74 | — |
| `contact-lynomia-support` | troubleshooting | فتح تذكرة مع لينوميا | 20 | 1000 | 806 | 0.81 | — |
| `troubleshooting` | troubleshooting | عندما لا يعمل شيء | 10 | 859 | 747 | 0.87 | — |
| `whatsapp-business-scoped-contacts` | whatsapp-errors | جهات اتصال واتساب ذات النطاق التجاري، وما لا يُرسل إليها | 130 | 391 | 315 | 0.81 | yes |
| `whatsapp-contact-info-requests` | whatsapp-errors | رُفض طلب معلومات جهة الاتصال | 120 | 455 | 375 | 0.82 | yes |
| `whatsapp-display-name` | whatsapp-errors | لم يُعتمد الاسم المعروض | 80 | 330 | 264 | 0.80 | yes |
| `whatsapp-error-131042` | whatsapp-errors | الخطأ 131042 — حساب واتساب للأعمال غير قابل للفوترة | 20 | 463 | 393 | 0.85 | yes |
| `whatsapp-error-131049` | whatsapp-errors | الخطأ 131049 — رفض واتساب الرسالة لهذا الشخص وحده | 10 | 529 | 433 | 0.82 | yes |
| `whatsapp-error-131053` | whatsapp-errors | الخطأ 131053 — لم يستطع واتساب جلب الملف | 30 | 405 | 321 | 0.79 | yes |
| `whatsapp-error-131060` | whatsapp-errors | الخطأ 131060 — رسالة واردة لا يسلّمها واتساب | 40 | 360 | 290 | 0.81 | yes |
| `whatsapp-error-190` | whatsapp-errors | الخطأ 190 — رمز وصول واتساب لم يبقَ صالحاً | 50 | 437 | 361 | 0.83 | yes |
| `whatsapp-find-a-failed-message` | whatsapp-errors | إيجاد المحادثات التي فشلت فيها رسالة | 140 | 571 | 463 | 0.81 | yes |
| `whatsapp-nothing-arrives` | whatsapp-errors | لا يصل شيء من واتساب | 90 | 522 | 423 | 0.81 | yes |
| `whatsapp-number-already-connected` | whatsapp-errors | «توجد قناة لهذا الرقم بالفعل» | 110 | 391 | 285 | 0.73 | yes |
| `whatsapp-number-status` | whatsapp-errors | مُعلَّم ومقيَّد ومحجوب — ماذا تعني حالة الرقم | 60 | 533 | 436 | 0.82 | yes |
| `whatsapp-quality-and-limits` | whatsapp-errors | تقييم الجودة وحدود الإرسال | 70 | 557 | 460 | 0.83 | yes |
| `whatsapp-reconnect-a-number` | whatsapp-errors | إعادة ربط رقم واتساب | 100 | 529 | 442 | 0.84 | yes |
| `connect-whatsapp` | whatsapp | ربط رقم واتساب | 10 | 1193 | 950 | 0.80 | — |
| `the-whatsapp-24-hour-window` | whatsapp | نافذة الـ24 ساعة في واتساب | 30 | 867 | 686 | 0.79 | — |
| `whatsapp-business-coexistence` | whatsapp | تطبيق WhatsApp Business ولينوميا تشات على رقم واحد | 20 | 988 | 780 | 0.79 | — |
| `whatsapp-template-lifecycle` | whatsapp | دورة حياة القالب | 50 | 1178 | 956 | 0.81 | — |
| `whatsapp-templates` | whatsapp | قوالب واتساب | 40 | 1327 | 1108 | 0.83 | — |
| `whatsapp-troubleshooting` | whatsapp | حين لا يعمل واتساب | 60 | 1223 | 997 | 0.82 | — |
| `roles-and-permissions` | workspace | الأدوار والصلاحيات | 30 | 893 | 804 | 0.90 | — |
| `set-up-an-inbox` | workspace | إعداد قناة تواصل | 10 | 853 | 826 | 0.97 | — |
| `teams-and-agents` | workspace | الفرق ووكلاء الدعم | 20 | 910 | 767 | 0.84 | — |
| `your-own-help-centre` | workspace | التوثيق والدعم | 40 | 535 | 426 | 0.80 | — |

---

## 2. Per-article verdict

The Arabic files are not independent articles: each is the sibling of an English file, linked by
`associated_article_id` (`custom/app/services/documentation/content_seeder.rb:77,90-92`) and sharing the English
file's `doc_key`. **No Arabic file can be retired, split or relocated independently of its English sibling** —
those verdicts belong to agents 049–060 and 062. What is in scope here is whether the Arabic text, as Arabic, is
fit to ship.

On that basis:

| Verdict | Count | Files |
|---|---|---|
| **KEEP** — Arabic is correct and ships as-is | 43 | everything not listed below |
| **REWRITE** (localised passages, not whole articles) | 14 | see table |
| **EXPAND** | 0 | Arabic is never thinner than English beyond the normal ratio |
| **SPLIT / MERGE / RETIRE / RELOCATE** | 0 | not an Arabic-layer decision |

The 14 REWRITE files, and what specifically must change:

| AR file | What must be rewritten |
|---|---|
| `ar/workspace/set-up-an-inbox.md` | five of nine inbox tab names are wrong in Arabic (§3.1) |
| `ar/workspace/roles-and-permissions.md` | claims to use "the names the product uses" for six permissions; five are English on screen (§3.2); nav path `الأدوار المخصصة` is wrong |
| `ar/whatsapp-errors/whatsapp-nothing-arrives.md` | both actionable UI references in "the one to check first" are wrong (§3.3) |
| `ar/whatsapp-errors/whatsapp-number-already-connected.md` | title and body translate an error string the Arabic product shows in English (§3.4) |
| `ar/whatsapp-errors/whatsapp-error-131053.md` | `سلامة الحساب` → `Account Health` |
| `ar/whatsapp-errors/whatsapp-error-190.md` | `التهيئة` ×2 → `الإعدادات`; a fifth variant of "Embedded Signup" (§4.2) |
| `ar/whatsapp-errors/whatsapp-reconnect-a-number.md` | `التهيئة` ×2; third variant of "Embedded Signup" |
| `ar/troubleshooting/commerce-store-needs-reconnecting.md` | `الإعدادات ← التجارة` points at a Reports label, not Settings (§3.5); provider names transliterated against corpus policy |
| `ar/troubleshooting/commerce-keys-cannot-do-that.md` | provider names transliterated |
| `ar/troubleshooting/commerce-store-address-refused.md` | provider names transliterated |
| `ar/troubleshooting/commerce-store-unreachable.md` | provider names transliterated; brand gender |
| `ar/troubleshooting/contact-lynomia-support.md` | brand gender disagrees with itself inside one file (§5.4) |
| `ar/contacts/custom-attributes.md` | both segments of the nav path wrong ×2 |
| `ar/contacts/bulk-actions.md` + `ar/conversations/labels.md` | `تعيين الوسوم` → `إضافة وسم` |

Plus one-line corrections in `ar/automation/automation-rules.md:72`, `ar/commerce/connect-salla.md:24`,
`ar/commerce/connect-zid.md:23`, `ar/commerce/commerce-overview.md:21`, `ar/commerce/connect-woocommerce.md:90`
and the four `إضافة قناة` near-misses, none of which justifies a REWRITE verdict on its own.

---

## 3. Accuracy against the product

Method: every `**bold**` run and every `«guillemet»` string in the Arabic corpus was normalised and matched
against an index of all 8,408 Arabic dashboard strings plus `config/locales/ar.yml`. The corpus contains **47
distinct bolded navigation paths**. Of those, 26 resolve entirely to real Arabic UI strings, 10 contain a segment
I confirmed wrong, 4 contain a near-miss, and 7 contain a segment I could not verify from the locale files
(user-entered values such as `hawalli`, or labels that live in a component rather than the locale index).

**What is right is worth stating, because it is most of it.** These Arabic quotes are character-exact against the
Arabic UI: `الإعدادات ← قنوات التواصل` (`app/javascript/dashboard/i18n/locale/ar/settings.json:353`),
`الإعدادات ← خيارات الربط` (`settings.json:357`), `الإعدادات ← المتجر` (`settings.json:358`),
`الإعدادات ← الروبوتات` (`settings.json:351`), `منشئ التدفقات` (`flowBuilder.json:3`), `القوالب`
(`whatsappTemplateMgmt.json:3`), `المتعاونون` and `ساعات العمل` (`inboxMgmt.json:780,784`), `اختر صندوق الوارد`
(`campaign.json:38`), the five priority options `لا يوجد / منخفضة / متوسطة / عالية / عاجل`
(`conversation.json:207-211`), `إدارة طلبات المتجر (تغيير الحالة وإعادة إرسال رسائل المتجر)`
(`customRole.json:48`), `Connect with WhatsApp Business` (`inboxMgmt.json:425`), `Account Health`
(`inboxMgmt.json:787`) and `لوحة Shopify ← الإعدادات ← النطاقات` (`commerce.json:278`). Somebody checked.

### 3.1 `set-up-an-inbox` names five of nine inbox tabs wrong — **wrong**

`ar/workspace/set-up-an-inbox.md:41-48` presents the inbox tabs as a table of bolded labels. Against
`app/javascript/dashboard/i18n/locale/ar/inboxMgmt.json:778-790`:

| Article | Line | Actual Arabic UI | Cite |
|---|---|---|---|
| `**الإعدادات**` | :41 | `الإعدادات` | `inboxMgmt.json:779` — correct |
| `**المتعاونون**` | :42 | `المتعاونون` | `inboxMgmt.json:780` — correct |
| `**ساعات العمل**` | :43 | `ساعات العمل` | `inboxMgmt.json:784` — correct |
| `**رضا العملاء**` | :44 | `تقييم رضاء العملاء` | `inboxMgmt.json:788` — **wrong** |
| `**نموذج ما قبل المحادثة**` | :46 | `نموذج ما قبل الدردشة` | `inboxMgmt.json:783` — **wrong** |
| `**التهيئة**` | :46 | `الإعدادات` | `inboxMgmt.json:781` — **wrong** |
| `**تهيئة البوت**` | :47 | `اعدادات البوت` | `inboxMgmt.json:786` — **wrong** |
| `**سلامة الحساب**` | :47 | `Account Health` | `inboxMgmt.json:787` — **wrong** |
| `**المكالمات**` | :48 | `Voice` / `Calls` | `inboxMgmt.json:789-790` — **wrong** |

Two of these are the product's fault, not the article's: `inboxMgmt.json:781` gives the Configuration tab the
*same* Arabic label as the Settings tab (`الإعدادات`), which is why an author reached for `التهيئة`; and
`inboxMgmt.json:786` misspells `اعدادات` (missing hamza). Both belong in the product-fix list, not the corpus
one. But `Account Health`, `Voice` and `Calls` are untranslated English on screen and the article invents Arabic
for them.

`سلامة الحساب` is also used at `ar/whatsapp-errors/whatsapp-error-131053.md:32` — while
`ar/whatsapp/connect-whatsapp.md:61` quotes the same tab correctly as `Account Health`. The corpus contradicts
itself about one tab.

### 3.2 `roles-and-permissions` claims the product's own names, and five of six are English — **wrong**

`ar/workspace/roles-and-permissions.md:27-28` says: *"وهذه الخيارات الستّة، بالأسماء التي يستخدمها المنتج"* —
"these are the six options, named as the product names them." The table at :32-37 then gives six Arabic names.
Against `app/javascript/dashboard/i18n/locale/ar/customRole.json:43-50`, five of the six are English on screen:

| Article :line | Arabic given | Actual Arabic UI | Cite |
|---|---|---|---|
| :32 | إدارة جميع المحادثات | `Manage all conversations` | `customRole.json:43` |
| :33 | إدارة المحادثات غير المُسندة والمُسندة إليه | `Manage unassigned conversations and those assigned to them` | `customRole.json:44` |
| :34 | إدارة المحادثات المشارك فيها والمُسندة إليه | `Manage participating conversations and those assigned to them` | `customRole.json:45` |
| :35 | إدارة جهات الاتصال | `Manage contacts` | `customRole.json:46` |
| :36 | إدارة التقارير | `Manage reports` | `customRole.json:47` |
| :37 | إدارة طلبات المتجر (تغيير الحالة وإعادة إرسال رسائل المتجر) | identical | `customRole.json:48` — correct |

The Arabic is a reasonable translation of each English label. The problem is the explicit promise that these are
what the reader will see. Either the five labels get translated in the product, or the sentence at :27-28 has to
stop claiming it.

Two further defects, both inherited from the English:

- The count **six** is wrong. `app/javascript/dashboard/constants/permissions.js:4-12` offers **seven**:
  `support_ticket_manage` is in the list and in the Arabic UI as `إدارة كل حالات الدعم في الحساب`
  (`customRole.json:50`), and the article does not mention it at all. `ar/.../roles-and-permissions.md:90` repeats
  the claim ("ثابتة على البنود الستّة"). The English has the same error
  (`en/workspace/roles-and-permissions.md:3,28`), so this is 057/062's to fix in both languages — but the Arabic
  must not be corrected in isolation.
- `ar/.../roles-and-permissions.md:67` instructs `الإعدادات ← الأدوار المخصصة`. The Arabic sidebar entry is
  `Custom Roles` in English (`settings.json:400`). `الأدوار المخصصة` exists in the Arabic UI only inside a
  paywall notice body (`customRole.json:25`), never as a navigation label.

### 3.3 `whatsapp-nothing-arrives` gets both of its actions wrong — **wrong**

This is the article for the commonest cause of total WhatsApp silence, and both of its two actionable UI
references are strings that do not exist in Arabic:

| `ar/whatsapp-errors/whatsapp-nothing-arrives.md:14` | Actual Arabic UI | Cite |
|---|---|---|
| `**Webhook غير مُهيّأ**` | `Webhook not configured` | `inboxMgmt.json:990` |
| `اضغط **تسجيل Webhook**` | `Register Webhook` | `inboxMgmt.json:991` |

`ar/whatsapp/whatsapp-troubleshooting.md:61,74` quotes **the same two strings correctly**, in Latin. So do
`ar/whatsapp/connect-whatsapp.md:108` and `ar/whatsapp/whatsapp-business-coexistence.md:96`. One file out of four
half-translated them, and it is the file a stuck user reaches first.

### 3.4 `whatsapp-number-already-connected` translates an untranslated error — **wrong**

The Arabic title is `«توجد قناة لهذا الرقم بالفعل»` (`ar/whatsapp-errors/whatsapp-number-already-connected.md:2`),
repeated in the body at :9, presented as the literal refusal. The string an Arabic-locale user actually sees is
English: `Channel already exists for this phone number: %{phone_number}, please contact support if the error
persists` (`config/locales/ar.yml:151`). The entire `whatsapp:` error block at `config/locales/ar.yml:147-158` is
untranslated, including `message_outside_messaging_window` (:152), which the 24-hour-window article depends on.

The English title quotes the string exactly, so an English reader who pastes what they saw into search finds the
article. **The Arabic article contains the Latin string nowhere** — not in the title, not in the body, not in
`seo_title`, not in `seo_description`. I verified this mechanically: `Channel already exists`,
`Message not sent because`, `access token does not have` and `Failed to reauthorize` appear in **zero** AR files.

The commerce troubleshooting set does this correctly: `INVALID_STORE_URL`, `AUTH_INVALID`, `STORE_UNAVAILABLE`,
`ORDER_CHANGED`, `NOT_APPLIED`, `REFUND_DECLINED`, `missing_scope` and `write_orders` are all preserved verbatim in
the Arabic files. The practice exists; it just was not applied to the WhatsApp error strings.

### 3.5 `commerce-store-needs-reconnecting` sends the reader to the wrong settings page — **wrong**

`ar/troubleshooting/commerce-store-needs-reconnecting.md:12` and `:18` both instruct
`الإعدادات ← التجارة`. The Arabic Settings entry for Commerce is `المتجر`
(`app/javascript/dashboard/i18n/locale/ar/settings.json:358`, confirmed by `commerce.json:12`
*"اربط متجرًا من الإعدادات ← المتجر"*). `التجارة` is the Arabic label for the **Reports** Commerce page
(`settings.json:331` `ANALYTICS_COMMERCE`). An Arabic reader following this article looks for Commerce under
Settings, finds `المتجر`, and has been told to look for something that only exists under Reports.

`ar/commerce/commerce-overview.md:64` gets the same path right (`الإعدادات ← المتجر ← إضافة متجر`). Same seam
again.

### 3.6 Other confirmed mismatches

| AR file:line | Quotes | Actual Arabic UI | Cite |
|---|---|---|---|
| `ar/automation/automation-rules.md:72` | `**الإعدادات ← الأتمتة ← إنشاء أتمتة**` | button reads `Create Automation` | `automation.json:7` |
| `ar/contacts/custom-attributes.md:59`, `:90` | `**الإعدادات ← السمات المخصصة ← إضافة سمة مخصصة**` | `سمات مخصصة` / `إضافة سمة خاصة` | `settings.json:365`, `contact.json:207` |
| `ar/contacts/bulk-actions.md:87` | `**تعيين الوسوم ← hawalli**` | `إضافة وسم` | `bulkActions.json:29` |
| `ar/conversations/labels.md:89` | `**تعيين الوسوم ← wholesale**` | `إضافة وسم` | `bulkActions.json:29` |
| `ar/commerce/connect-salla.md:24` | `**... ← Salla**` | `سلة` | `commerce.json:6` |
| `ar/commerce/connect-zid.md:23` | `**... ← Zid**` | `زد` | `commerce.json:7` |
| `ar/whatsapp-errors/whatsapp-reconnect-a-number.md:14`, `ar/.../whatsapp-error-190.md:30,31` | `**التهيئة**` | `الإعدادات` | `inboxMgmt.json:781` |
| `ar/whatsapp/connect-whatsapp.md:48,66`; `ar/whatsapp/whatsapp-business-coexistence.md:10,56` | `**إضافة قناة**` | `إضافة قناة تواصل` | `settings.json:311` — near-miss |

**Unverified**, and why: `الفلتر` (`ar/audiences-and-campaigns/shared-audiences.md:116`), `إضافة روبوت`
(`ar/automation/agent-bots.md:33`), `البيانات` (`ar/contacts/import-contacts.md:138`), `المرشِّح` and
`تسليم الرسائل` (`ar/whatsapp-errors/whatsapp-find-a-failed-message.md:30`) are not present as values in any
`locale/ar/*.json` file or in `config/locales/ar.yml`. They are either component-local strings outside the locale
index or they are wrong; distinguishing the two needs the running UI, which I did not have.

### 3.7 The underlying cause: the Arabic product is 37% English

Measured across all 54 files in `app/javascript/dashboard/i18n/locale/ar/`: **3,126 of 8,408 strings (37.2%)
contain no Arabic character at all** and are byte-identical to the English. `config/locales/ar.yml` is comparable:
**250 of 519 value lines (48%)** carry no Arabic.

The worst offenders are exactly the areas the corpus documents most heavily:

| AR locale file | Strings | No Arabic | Share |
|---|---|---|---|
| `integrations.json` | 892 | 619 | 69% |
| `inboxMgmt.json` | 997 | 473 | 47% |
| `settings.json` | 732 | 428 | 58% |
| `helpCenter.json` | 655 | 358 | 55% |
| `contact.json` | 594 | 124 | 21% |
| `conversation.json` | 409 | 134 | 33% |
| `campaign.json` | 186 | 81 | 44% |
| `customRole.json` | 60 | 37 | 62% |
| `sla.json` | 72 | 48 | 67% |
| `mfa.json` | 98 | 80 | 82% |
| `onboarding.json` | 74 | 61 | 82% |
| `webhooks.json` | **1 key in total** | 0 | — the whole webhooks UI has one Arabic string, `إعدادات الـ Webhook` |

Whole flows are English in Arabic: the manual WhatsApp setup (`inboxMgmt.json:344,352,361,362,367,406,407`),
Embedded Signup (`inboxMgmt.json:1079-1081`, `:843`, `:425`), assignment policies
(`settings.json`, the entire `ASSIGNMENT_POLICY` block), SLA (`sla.json:4-6,9-10,...`), custom roles
(`customRole.json:3-8,43-47`). `platformSupport.json` and `supportTickets.json` are, by contrast, fully Arabic —
those are Lynomia's own additions and were localised properly.

**This is the single constraint that governs how the Arabic corpus can be fixed.** An Arabic article cannot quote
an Arabic UI label that does not exist. Every mismatch in §3.1–3.6 is either "translate the product" or "quote
the English". That is a product decision and it has to be made before the corpus is rewritten, or the corpus will
be rewritten twice.

