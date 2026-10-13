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

---

## 4. Missing articles

The Arabic corpus is missing nothing the English corpus has — parity is exact. Two gaps are Arabic-specific.

### 4.1 Support tickets (the account's own case management) has no article in either language

`app/javascript/dashboard/i18n/locale/ar/supportTickets.json` is a fully localised, 192-string feature:
`حالات الدعم`, with statuses, priorities, SLA state, assignment and a reference number. It is gated by the
`support_ticket_manage` permission (`app/javascript/dashboard/constants/permissions.js:11`). **No corpus file
covers it**, and the permission is missing from `roles-and-permissions` (§3.2).

This matters for Arabic specifically because the Arabic UI has two distinct, similarly-named things:
`حالات الدعم` (the account's own cases, `supportTickets.json:HEADER`) and `تذاكري` / `تذكرة` (tickets raised with
Lynomia, `platformSupport.json:SIDEBAR.MY_TICKETS`). The corpus documents only the second
(`ar/troubleshooting/contact-lynomia-support.md`, title `فتح تذكرة مع لينوميا`). An Arabic reader who sees
`حالات الدعم` in their sidebar and searches the help centre for it finds an article about writing to Lynomia.

### 4.2 No article anchors Meta's Embedded Signup under any Arabic name

The corpus uses **five** different Arabic renderings for Meta's embedded signup flow, and the product shows a
sixth, in English:

| Rendering | Where | Count |
|---|---|---|
| `الإعداد السريع` | `ar/whatsapp/connect-whatsapp.md:28,50,67,...` | 5 |
| `التجهيز السريع` | `ar/getting-started/connect-your-first-channel.md:99,...` | 4 |
| `التسجيل الموجَّه` | `ar/whatsapp-errors/whatsapp-reconnect-a-number.md`, `ar/.../whatsapp-error-190.md` | 5 |
| `تسجيل واتساب الموجَّه` | `ar/whatsapp-errors/whatsapp-error-190.md:30` | 1 |
| `نافذة Meta` | `connect-whatsapp.md`, `whatsapp-business-coexistence.md`, `connect-your-first-channel.md` | 10 |
| **`WhatsApp Embedded Signup`** | the product, in English | `inboxMgmt.json:1079-1081` |

`ar/whatsapp/connect-whatsapp.md:50` does quote the button correctly — *Connect with WhatsApp Business*,
matching `inboxMgmt.json:425`. That is the one anchor an Arabic reader can match on screen, and it appears once in
63 files. Nothing in Arabic ties any of the five phrases to the official Meta term, so Arabic search for
"Embedded Signup" — which is what Meta's own documentation, Meta's support and the product itself say — returns
nothing.

### 4.3 Not a gap: Arabic search synonyms

Arabic readers will search for transliterations (`واتساب`, `ويب هوك`, `شوبيفاي`) and for the Latin forms. The
corpus contains `واتساب` ×406 and `WhatsApp` ×67, so WhatsApp is covered both ways. `ويب هوك` appears **zero**
times against `Webhook`/`webhook` ×86, and `ميتا` appears **zero** times against `Meta` ×137. Whether that is a
gap depends on the portal's search behaviour, which is agent 077/078's to measure, not mine. Recorded, not
claimed.

---

## 5. Quality

### 5.1 The Arabic is genuine, and the evidence is specific

I looked for the signatures of machine translation and did not find them.

- **Orthography is clean.** Zero occurrences of the classic MT/typing errors across all 63 files: no bare alif
  for hamza at word start, no `الى` for `إلى`, no `الي` for `إلى`. Measured mechanically.
- **Partial vocalisation is deliberate.** 4,224 tashkeel marks across all 63 files — shadda and short vowels
  placed on exactly the forms that are ambiguous unvocalised (`تُسلَّم`, `يُرسَل`, `مُعلَّم`, `المُدخَلات`).
  No MT pipeline does this, and no translator does it by accident in every file.
- **Punctuation is Arabic.** 2,325 Arabic commas `،`. **Zero** Latin commas followed by Arabic, **zero** Latin
  question marks after Arabic, two stray Latin semicolons (`ar/getting-started/invite-your-team.md`,
  `ar/getting-started/set-up-your-account.md`).
- **Structure is sometimes better than the English.** `ar/workspace/set-up-an-inbox.md:16-26` converts the
  English prose list of nine channels (`en/.../set-up-an-inbox.md:17-21`) into a two-column table, and adds a
  sentence at :77 about the two receptionists that has no English counterpart. `ar/workspace/roles-and-permissions.md:13-20`
  splits the English four-row comparison table (`en/.../roles-and-permissions.md:14-19`) into six rows,
  separating settings from billing and contacts from canned responses. These are editorial decisions, not
  translation artefacts.
- **The register holds.** Technical passages such as `ar/integrations/webhooks.md:70-90` (HMAC verification,
  header names, raw-byte hashing, constant-time comparison) read as native Arabic technical prose, not as
  transposed English.

Verdict: **genuine**, with the caveat that it is a *translation* — it follows the English paragraph for paragraph
and inherits the English's factual errors (§3.2). It is not independently authored Arabic.

### 5.2 RTL hazards in the corpus itself: mostly clean, four real ones

| Hazard | Measured | Verdict |
|---|---|---|
| Bidi control characters (RLM, LRM, ALM, LRI/RLI/FSI/PDI, RLE/LRE/PDF) | **1 occurrence in 63 files** | a stray U+200F at the start of `ar/commerce/connect-woocommerce.md:90`, an accident, not a policy |
| Zero-width and NBSP characters | **0** | clean |
| Arabic-Indic digits `٠-٩` | **16 in 5 files** | **inconsistent** — see below |
| Latin comma / question mark in Arabic prose | **0 / 0** | clean |
| Quotation convention | **116 `«»` in 35 files, 118 `"` in 14 files, 0 files mixing** | **inconsistent** — see below |

**Digit systems collide on the most-cited number in the product.** The 24-hour window is written with
Arabic-Indic digits in `getting-started` — `٢٤ ساعة` at `ar/getting-started/connect-your-first-channel.md:38,105`
and `ar/getting-started/your-first-conversation.md:97,116` — and with Western digits everywhere else, including
the dedicated article's own title, `نافذة الـ24 ساعة في واتساب`
(`ar/whatsapp/the-whatsapp-24-hour-window.md:2`). Western digits win 41 occurrences to 4. Two more files carry
stray Arabic-Indic digits: `ar/getting-started/set-up-your-account.md:57` (`من ٩ إلى ٦`),
`ar/getting-started/your-first-conversation.md:88` (`٣ أكتوبر، خط السائق ٧`),
`ar/troubleshooting/commerce-store-unreachable.md:23` (`٤٠ دقيقة`),
`ar/whatsapp/whatsapp-templates.md:99` (`الأحد ١٢`). Because the product's own UI, every error code and every API
value uses Western digits, Western digits are the only defensible policy; the `getting-started` section is the
outlier.

**Two quotation conventions, split cleanly by file, and one of them is an RTL defect.** 35 files use Arabic
guillemets `«…»`; 14 use Latin `"…"`; **no file mixes them**, which identifies this as two authoring passes
rather than carelessness. The 14 Latin-quote files are `administration/audit-logs.md`, all four `contacts/*`,
all six `conversations/*`, `integrations/webhooks.md`, `troubleshooting/troubleshooting.md` and
`workspace/teams-and-agents.md`.

This is not merely a style split. `«` and `»` are directional characters that the Unicode bidi algorithm mirrors
correctly in an RTL run; `"` is a single neutral codepoint used for both open and close, so it cannot be mirrored
and lands on the wrong side whenever the quoted run changes script. The clearest case is
`ar/conversations/macros.md:41`: `**"إسناد وكيل دعم" يتيح "Self".**` — an Arabic quoted phrase and a Latin quoted
token on one line, with four identical ambiguous quote marks between them. `ar/conversations/labels.md:42`
(`فـ "المشترون حديثاً"`) and `ar/conversations/macros-or-automation.md:32-33` have the same shape.

**The `الـ` + Latin token convention is inconsistent.** Four forms for two words:

| Form | Count |
|---|---|
| `الـ Webhook` (space, capitalised) | 22 |
| `الـwebhook` (no space, lowercase) | 14 |
| `الـ API` (space) | 4 |
| `الـAPI` (no space) | 4 |
| `الـ Secret`, `الـ consumer` | 3 |

`ar/automation/agent-bots.md:5` (seo_description) and `:8` use `الـwebhook`; `ar/integrations/webhooks.md`
uses `الـ Webhook` throughout. Same for `نافذة الـ24` (34) vs `نافذة الـ 24` (7). The kashida-plus-space form is
the better one — it gives the bidi algorithm a break opportunity and stops the Latin token fusing visually with
the Arabic article — but it has to be one or the other.

**Latent, in `ar/integrations/webhooks.md`:** the code span `` `sha256=` `` at :73 and :86 ends in `=`, a
weak-direction character. In an RTL paragraph the trailing `=` reorders to the left of the token and renders as
`=sha256`. The fenced block at :75-77 (`sha256=HMAC_SHA256(secret, "<timestamp>.<raw body>")`) will mirror its
parentheses and angle brackets unless the `<pre>` is forced `dir="ltr"`. Neither bites today — because of §5.3.

### 5.3 The renderer never declares RTL — **blocker**

All three portal layouts emit `lang` and no `dir`:

- `app/views/layouts/portal.html+documentation.erb:2` — `<html lang="<%= html_lang_attribute(I18n.locale) %>">`
- `app/views/layouts/portal.html.erb:2` — same
- `app/views/layouts/portal.html+plain.erb:2` — same
- `app/helpers/portal_helper.rb:40-42` — `html_lang_attribute` returns the locale string and nothing else

`grep -rn 'dir=' app/views/layouts/ app/views/public/` returns **nothing**. The article body wrapper
(`app/views/public/api/v1/portals/articles/_content.html.erb:6-17`) sets no direction either.

Direction is applied **client-side, after load**, by
`app/javascript/portal/portalHelpers.js:153-162` (`setDirectionAttribute`), called from `initialize()` at `:168`.
It reads `html.lang` and sets `html.dir = 'rtl'` when the language is in the RTL list — `ar` is in that list
(`app/javascript/dashboard/components/widgets/conversation/advancedFilterItems/languages.js:747`).

Consequences, all of which fall only on Arabic:

1. **Every Arabic article is served LTR and flips after the `portal` bundle executes.** A visible direction flash,
   and layout shift that counts against Core Web Vitals on exactly the 63 Arabic pages.
2. **The `rtl:` Tailwind variants in the documentation layout never match in the served HTML**, because they
   compile to `[dir="rtl"] &`. `app/views/public/api/v1/portals/documentation_layout/_sidebar.html.erb:15` carries
   `ltr:left-0 rtl:right-0`, `ltr:border-r rtl:border-l` and `max-md:ltr:-translate-x-full
   max-md:rtl:translate-x-full`; `app/views/public/api/v1/portals/_header.html.erb:6,15,47,107` and
   `_authors.html.erb:4` the same. Until the JS runs, the sidebar is on the wrong side and the mobile drawer
   slides from the wrong edge.
3. **Table columns and cell alignment are LTR.** `_content.html.erb:14-15` uses `[&_th]:!text-start` and
   `[&_td]:!text-start`; under LTR, `start` is left. The corpus is table-heavy — `ar/workspace/set-up-an-inbox.md`
   alone has 17 table rows — and the first column renders on the left.
4. **Arabic sentence-final punctuation reorders.** In an LTR paragraph, a trailing `.` after an Arabic word is
   placed at the far left of the line rather than after the word.
5. **The `<title>` is LTR.** `app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:10`
   composes `article.title + " | " + portal.display_title`; two Arabic strings around a neutral pipe in an LTR
   context put the separator in the wrong place in the tab and the search result.
6. **Nothing in the markup tells a crawler or an accessibility tool the page is RTL.**

The fix is one attribute on three layouts, derived from the locale the controller already resolved
(`app/controllers/public/api/v1/portals/base_controller.rb:53-64` sets `@locale` from the article). It is not a
corpus fix, and no amount of corpus work compensates for it. Owned by whoever takes the portal rendering —
flagging it here because it is the largest single Arabic-quality defect in the system and it was not going to be
found by reading Markdown.

**Unverified, adjacent, and worth somebody's attention:**
`app/controllers/public/api/v1/portals/base_controller.rb:38-43` — `set_locale` calls
`switch_locale_with_article(&)` (which yields inside `I18n.with_locale`) and then yields **again** at :42
unconditionally. If the second yield is the one whose render survives, the view renders outside
`I18n.with_locale('ar')` and `lang` comes back as the default locale — in which case
`setDirectionAttribute` never sets `rtl` at all and Arabic articles are permanently LTR. I could not test this
without running a request. It needs a request spec, not a code read.

### 5.4 Brand name and brand gender

**Three brand-name policies coexist.** `لينوميا تشات` ×244 in 59 files is the dominant form. But `Lynomia Chat`
appears in Latin ×7 in 4 files, including three `seo_description` values:
`ar/automation/automation-or-flow-builder.md:6`, `ar/automation/flow-builder.md:6`,
`ar/automation/automation-rules.md:6`, and in body prose at `ar/automation/automation-rules.md:38` and
`ar/automation/agent-bots.md:8,76`. The `automation/` section is the outlier: three of its four files use the
Latin form in SEO metadata while every other section uses the Arabic. `ar/commerce/connect-woocommerce.md:74`
correctly keeps `Lynomia Commerce` in Latin — that is a literal webhook name in WooCommerce and must stay.

**Grammatical gender disagrees with itself.** As a subject, `لينوميا تشات` takes masculine agreement in roughly
thirty places (`يقرأ`, `يُرسل`, `يحسب`, `يفرض`, `يتحقق`, `يرفض`, `يستطيع`, `يُظهر`, `يسجّل`, `يوسم`, …), which is
correct — `تشات` is the masculine head noun. Three places use feminine agreement with the same full name:
`ar/workspace/your-own-help-centre.md:6` (`تنشر لينوميا تشات`), `:15` (`لا تمنح لينوميا تشات`) and
`ar/workspace/roles-and-permissions.md:46` (`وتنشر لينوميا تشات`).

Bare `لينوميا` is worse: it is **feminine in six places** and **masculine in one, inside the same file** —
`ar/troubleshooting/contact-lynomia-support.md:51` has `لينوميا يعمل` while `:77` and `:110` have
`لينوميا لا تصل`. The other feminine uses are `ar/troubleshooting/commerce-store-unreachable.md:2` (the article
title), `commerce-keys-cannot-do-that.md:46`, `commerce-store-address-refused.md:46`,
`commerce-order-action-did-not-apply.md:27`, and `ar/whatsapp-errors/whatsapp-contact-info-requests.md:10` is
masculine (`يستطيع لينوميا`).

This is the kind of defect no English reviewer can see and no automated check will catch. The brand needs a
declared grammatical gender, and it needs to be the same for `لينوميا` and `لينوميا تشات`.

### 5.5 Front matter and SEO fields

**Both languages pass the audit cleanly.** Measured against `lib/tasks/documentation_seo_audit.rake:17-19`
(`MIN_DESCRIPTION 50`, `MAX_DESCRIPTION 160`, `MAX_TITLE 60`) using the seeder's own resolution
(`seo_title || title`, `seo_description || description`, `custom/app/services/documentation/content_seeder.rb:106-113`):

| | titles over 60 chars | descriptions outside 50–160 | missing descriptions |
|---|---|---|---|
| EN | 0 | 0 | 0 |
| AR | 0 | 0 | 0 |

That matches the reported production run of `0 SEO errors`. Three observations:

1. **`seo_title` never reaches the `<title>` element.**
   `app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:10` uses `article.title`,
   while `:26,38,50` use `meta["title"]` (the `seo_title`). So the fourteen Arabic `seo_title` values such as
   `خطأ واتساب 131049 في لينوميا تشات` (`ar/whatsapp-errors/whatsapp-error-131049.md:6`) reach `<meta name="title">`,
   `og:title` and `twitter:title` but never the browser tab or the search result's clickable line. This is
   language-neutral and belongs to agent 070/073; it matters more in Arabic because the `seo_title` values are
   the ones carrying the searchable `خطأ واتساب <code>` phrasing.
2. **The 50–160 band is not Arabic-aware.** It is a character count
   (`documentation_seo_audit.rake:88-93`, Ruby `String#length`) calibrated for Latin. Arabic writes no short
   vowels and fuses the article and prepositions, so a 160-character Arabic description carries materially more
   content than a 160-character English one, and Google truncates by pixel width rather than characters. The band
   is not wrong — nothing in the corpus fails it — but it is not measuring the same thing in the two languages.
   Recorded for agent 073.
3. **No `og:locale`.** `_meta_head.html.erb:34-43` emits no `og:locale`, so a social crawler is not told the
   Arabic page is Arabic. hreflang itself is correct: `:19-24` emits one `hreflang` per published sibling plus
   `x-default`, built from `custom/app/helpers/documentation_helper.rb:44-60`.

**Arabic article slugs are Latin.** `custom/app/services/documentation/content_seeder.rb:85-87` derives the
Arabic slug as `"#{key}-ar"`, so the Arabic URL is
`/hc/lynomia-docs/articles/whatsapp-error-131049-ar` — no Arabic keyword in the address. This is a defensible
decision (it keeps slugs ASCII and the `-ar` convention is load-bearing per `01-current-system.md` §10), but it is
an Arabic SEO cost and it should be a recorded decision rather than an accident. Agent 073's call.

---

## 6. EN/AR parity

Parity is the strongest part of this corpus. Measured mechanically over all 63 pairs:

| Check | Result |
|---|---|
| File presence | 63/63, exact per-section parity |
| `position` | identical in all 63 pairs |
| `tags` | identical in all 63 pairs |
| `seo_title` presence | identical (14 files in both) |
| Internal links | **493 in each language**, and the set of link *targets* is identical in all 63 pairs |
| Structural divergence (headings, tables, lists, code spans, fences) | **10 of 63 files**, and in 9 of those the Arabic adds structure rather than losing it |
| Word ratio | 0.74–0.97, mean ≈0.86 — the expected band for EN→AR |

The ten divergent files, and what diverges:

| File | Ratio | Divergence |
|---|---|---|
| `workspace/set-up-an-inbox` | 0.97 | AR has 17 table rows vs EN 6 — the nine-channel prose list became a table (§5.1) |
| `workspace/roles-and-permissions` | 0.90 | AR 16 table rows vs 14; one extra bullet; one extra numbered step |
| `workspace/teams-and-agents` | 0.84 | AR one extra bullet |
| `whatsapp/whatsapp-template-lifecycle` | 0.81 | AR one extra `##`, one extra bullet, **three numbered steps where EN has none** |
| `whatsapp/whatsapp-templates` | 0.83 | AR one extra `##` |
| `commerce/commerce-provider-support` | 0.95 | AR 34 table rows vs 31 |
| `commerce/customer-360` | 0.89 | AR three extra bullets |
| `audiences-and-campaigns/whatsapp-campaigns` | 0.83 | AR two extra bullets |
| `integrations/webhooks` | 0.83 | AR one extra code span |
| `troubleshooting/commerce-store-unreachable` | 0.74 | AR **one fewer** code span — the only case where Arabic drops something |

**Semantic parity defects** (meaning, not shape):

1. **Link text drifts from target titles more in Arabic than in English.** 161 of 493 Arabic link texts differ
   from the target article's `title`, against 137 of 493 in English. Most of that is intentional inline phrasing
   in both languages. The Arabic-specific cases are the ones where the drift introduces a *second term* for the
   same feature: `ar/commerce/commerce-overview.md:21` links `[منشئ المسارات](flow-builder)` while eight other
   files link `[منشئ التدفقات]`; `ar/audiences-and-campaigns/labels-or-shared-audiences.md:61,130` link
   `[الإجراءات بالجملة](bulk-actions)` while `ar/administration/audit-logs.md:39` links
   `[الإجراءات الجماعية]`; `ar/whatsapp-errors/whatsapp-error-131049.md` links
   `[نافذة واتساب الـ 24 ساعة]` while the target's own title is `نافذة الـ24 ساعة في واتساب`.
2. **`ar/workspace/set-up-an-inbox.md:100`** links `[الإسناد وترتيب الأولوية](assign-and-prioritise)` while the
   target's title is `الإسناد والأولوية`.
3. **The `integrations` category name and its hub article disagree in Arabic, and only in Arabic.**
   `custom/db/documentation/manifest.yml:104` names the section `التكاملات`;
   `ar/integrations/integrations.md:2` titles the hub article `خيارات الربط`; the product's Arabic sidebar says
   `خيارات الربط` (`app/javascript/dashboard/i18n/locale/ar/settings.json:357`). The category name is the odd one
   out and it is the one a reader sees in the portal navigation. English has no such clash
   (`manifest.yml:101` `Integrations`, `en/integrations/integrations.md` `Integrations`). The Arabic UI is itself
   split here — `integrations.json:3` says `خيارات الربط` but `:5,6` say `التكاملات`.
4. **Inherited factual errors.** The "six permissions" error (§3.2) is in both languages
   (`en/workspace/roles-and-permissions.md:3,28`). The Arabic must not be corrected alone.

**Not a parity defect, and worth recording as a decision already made well:** the Arabic corpus systematically
renders the English word *inbox* as `قناة` / `قنوات التواصل` rather than `صندوق الوارد` — `ar/workspace/set-up-an-inbox.md`
is titled `إعداد قناة تواصل`, not `إعداد صندوق وارد`. That is not a mistranslation. It matches this
installation's own Arabic UI, where `Settings → Inboxes` reads `قنوات التواصل`
(`app/javascript/dashboard/i18n/locale/ar/settings.json:353`, `inboxMgmt.json:3`). The corpus reserves
`صندوق الوارد` (19 occurrences, 16 files) for the *conversation-list screen*, which is also what the Arabic UI
calls it (`settings.json:381` `صندوق الوارد الجديد`, `analytics.json:91` `صندوق الوارد`,
`campaign.json:38` `اختر صندوق الوارد`). An EN/AR diff tool will flag this as a mismatch on 36 occurrences; it is
correct and must not be "fixed". **Agent 094 should be told this before it refutes it.**

---

## 7. Proposed EN→AR terminology glossary

Columns: the term; what the corpus currently uses, with counts; what the product's Arabic UI uses, with a
citation; the recommendation; and the reason. Where the UI string is English, that is stated — because the
recommendation then depends on a product decision (§3.7) that has not been made.

| EN term | In the corpus today | In the Arabic UI | **Recommend** | Note |
|---|---|---|---|---|
| **inbox** (the entity in Settings) | `قناة` / `قنوات التواصل` / `قناة تواصل` (330) | `قنوات التواصل` (`settings.json:353`, `inboxMgmt.json:3`) | **`قناة تواصل`** / pl. `قنوات التواصل` | already correct and deliberate; do not "restore" `صندوق الوارد` |
| **inbox** (the conversation-list screen) | `صندوق الوارد` (19) | `صندوق الوارد` (`settings.json:381`, `analytics.json:91`) | **`صندوق الوارد`** | the two senses are genuinely distinct in this product; keep both terms, never interchange |
| **channel** | `قناة` | `القنوات` (`settings.json` `SIDEBAR.CHANNELS`) | **`قناة`** | collides with *inbox* above; in prose that must disambiguate, use `نوع القناة` for the channel type |
| **conversation** | `محادثة` / `المحادثات` (uniform) | `المحادثات` (`settings.json`, `conversation.json`) | **`محادثة`** | no variance found; already consistent |
| **contact** | `جهة الاتصال` / `جهات الاتصال` (232) | `جهة الاتصال` (`ar.yml:273`, `contact.json`, `supportTickets.json`) | **`جهة الاتصال`** | already consistent |
| **campaign** | `حملة` / `الحملات` (116) | `الحملات` (`ar.yml:187`, `campaign.json`) | **`حملة`** | already consistent |
| **template** | `قالب` / `القوالب` (238) | `القوالب` (`whatsappTemplateMgmt.json:3`) | **`قالب`** | already consistent. Keep `UTILITY`, `MARKETING`, `APPROVED`, `PENDING` etc. **untranslated** — the corpus already does |
| **webhook** | `Webhook` (53), `webhook` (33), `الـ Webhook` (22), `الـwebhook` (14); `ويب هوك` zero | `إعدادات الـ Webhook` (`webhooks.json:3` — the only Arabic string in the whole webhooks UI) | **`Webhook`**, Latin, capitalised, with `الـ Webhook` (kashida + space) when the article is needed | never transliterate; never lowercase; fix the 14 `الـwebhook` |
| **access token** | `رمز وصول` (10), `رمز الوصول` (7), `الرمز` (38); `توكن` zero | **English**: `Permanent access token`, `Paste access token` (`inboxMgmt.json:361-362`); `رمز وصول` only at `commerce.json:240` | **`رمز الوصول`** for prose, **and quote the English field label verbatim** until `inboxMgmt.json` is translated | `الرمز` alone is ambiguous with Salla/Zid connection codes, which are a different thing |
| **permission** | `صلاحية` / `الصلاحيات` (88); `إذن` (4); `تصريح` (12, authorization sense) | `Permissions` **English** (`customRole.json:49,65`); `الصلاحية` (`commerce.json:232`) | **`صلاحية`** for permission; **`تصريح`** reserved for *authorization* (OAuth); never `إذن` | the corpus already keeps the two senses apart — formalise it |
| **business portfolio** | `محفظة أعمال` / `محفظة الأعمال` (5); `Business Manager` / `Meta Business Manager` (3) | not present | **`محفظة الأعمال`** | Meta's own Arabic term; `Business Manager` is Meta's **retired** name and must go — see `ar/whatsapp-errors/whatsapp-error-131042.md:18,35,42` |
| **WABA / WhatsApp Business account** | `حساب واتساب للأعمال` (10), `حساب الأعمال` (9), `حساب WhatsApp Business` (1), `WABA` (1) | `WhatsApp Business Account ID` **English** (`inboxMgmt.json:406`) | **`حساب واتساب للأعمال`** on first use per article, `حساب الأعمال` thereafter; **`WABA` only beside the Latin field label** | four variants for one entity, all inside `whatsapp/` |
| **Embedded Signup** | `الإعداد السريع` (5), `التجهيز السريع` (4), `التسجيل الموجَّه` (5), `تسجيل واتساب الموجَّه` (1), `نافذة Meta` (10) | `WhatsApp Embedded Signup` **English** (`inboxMgmt.json:1079-1081`) | **`التسجيل المدمج (Embedded Signup)`** on first use, `التسجيل المدمج` thereafter; keep `نافذة Meta` only for the popup itself | five Arabic names for one flow; the Latin term must appear at least once per article so it is searchable |
| **provider** (commerce platform) | `منصة` / `المنصة` (≈28); `المزوّد` (5) | `PROVIDERS` → the four names (`commerce.json:4-8`) | **`منصة`** for commerce platforms; **`المزوّد`** only for SMS/voice carriers (Twilio, Bandwidth) | the corpus already splits this way by accident — make it policy |
| **integration** | `خيارات الربط` (8); `تكامل` / `التكاملات` (4 + `manifest.yml:104`) | `خيارات الربط` (`settings.json:357`, `integrations.json:3`), but `التكاملات` at `integrations.json:5,6` | **`خيارات الربط`** | and change `manifest.yml:104` from `التكاملات` to `خيارات الربط`; see §6.3 |
| **automation / automation rule** | `أتمتة` / `الأتمتة` / `قواعد الأتمتة` (177); `التشغيل الآلي` zero | `الأتمتة` (`settings.json`), `إضافة قاعدة أتمتة` (`automation.json:12`), but button is `Create Automation` **English** (`automation.json:7`) | **`قاعدة أتمتة`** / `قواعد الأتمتة` | already consistent in the corpus; the UI button is the problem |
| **flow / flow builder** | `تدفق` / `التدفقات` / `منشئ التدفقات` (131); **`مسار` / `المسارات` / `منشئ المسارات` (10 in the product sense)** | `منشئ التدفقات`, `التدفق` (`flowBuilder.json:3,6`) | **`تدفق`** / `منشئ التدفقات`; **retire `مسار` in the product sense entirely** | `مسار` is also used in the corpus for *URL path* (`commerce-store-address-refused.md:41`) and *failure path* (`agent-bots.md:126`); the collision makes `whatsapp-template-lifecycle.md:68` genuinely ambiguous |
| **SLA** | **absent from the corpus** | `اتفاقات مستوى الخدمة` (`sla.json:3`) **and** `اتفاقية الخدمة` (`supportTickets.json` TABLE.SLA) and `بلا سياسة اتفاقية خدمة`; rest of `sla.json` is English | **`اتفاقية مستوى الخدمة (SLA)`** on first use, `اتفاقية مستوى الخدمة` thereafter | the UI contradicts itself; no article exists to be consistent with yet |
| **support ticket** — two distinct features | Lynomia-facing: `تذكرة` / `تذاكري` (26, 2 files). Account's own cases: **absent** | Lynomia-facing: `تذكرة` / `تذاكري` (`platformSupport.json` SIDEBAR). Account's own: `حالات الدعم` / `حالة` (`supportTickets.json` HEADER) | **`تذكرة`** for a ticket raised with Lynomia; **`حالة دعم`** for the account's own case | the corpus is already right on the one it covers; §4.1 is the gap |
| **assignment / assign** | `إسناد` / `الإسناد` (135); `تعيين` (10) | **split in the UI**: `إسناد لي` (`conversation.json:45`) but `تعيين وكيل` / `تعيين فريق` (`conversation.json:238,243`) | **`إسناد`** | the corpus is *more* consistent than the product; fix the product toward the corpus |
| **label** | `وسم` / `الوسوم` (228); `تسمية` (10); `ملصق` (2, a deliberate metaphor at `labels-or-shared-audiences.md:3`) | **split in the UI**: `الوسوم` (`settings.json`, `labelsMgmt.json`, `bulkActions.json:29`) but `التسمية` / `التسميات` (`conversation.json:255`, `bulkActions.json:31`) | **`وسم`** / `الوسوم` | corpus is right; UI needs the fix |
| **agent** | `وكيل الدعم` / `وكلاء الدعم` (132); `موظف` (14, generic prose) | `وكيل الدعم` (`agentMgmt.json:27`), `الوكلاء` (`settings.json`), but `الموظفين` in `inboxMgmt.json:652` | **`وكيل الدعم`** for the role; `موظف` acceptable only in narrative examples | already workable |
| **bot / agent bot** | `روبوت` / `الروبوتات` (58); `بوت` (3, at `set-up-an-inbox.md:24,47`) | `الروبوتات` (`settings.json:351`, `agentBots.json:3`) | **`روبوت`** / `الروبوتات` | exception: `بوت على Telegram` at `set-up-an-inbox.md:24` is Telegram's own term and may stay |
| **troubleshooting** | `حل المشكلات` (`manifest.yml`), hub article titled `عندما لا يعمل شيء` | no UI equivalent | **`حل المشكلات`** for the category; article titles stay task-shaped | matches the English pattern; no change needed |
| **API** | `الواجهة البرمجية` (8); `الـAPI` (4); `الـ API` (4) | `API` (Latin, throughout) | **`الواجهة البرمجية (API)`** on first use, `الواجهة البرمجية` thereafter | pick one; `webhooks.md` and `agent-bots.md` currently disagree |
| **commerce / store** | `المتجر` (dominant); `التجارة` / `تجارة` (7, in `troubleshooting/` only) | `المتجر` (`settings.json:358`, `commerce.json:3`); `التجارة` is the **Reports** page (`settings.json:331`) | **`المتجر`** | `التجارة` under Settings is a wrong navigation path — §3.5 |

### 7.1 Must stay untranslated

These are product names, brand names, protocol tokens or machine-readable identifiers. The corpus is already
right about most of them; the exceptions are named.

**Brand and product names:** `WhatsApp` (alongside `واتساب` for the consumer-facing service — both are in use and
both are legitimate), `WhatsApp Business`, `WhatsApp Cloud API`, `Meta`, `Facebook`, `Messenger`, `Instagram`,
`Twilio`, `Bandwidth`, `Telegram`, `Line`, `TikTok`, `Slack`, `Dialogflow`, `Google Translate`, `OpenAI`,
`Linear`, `Notion`, `LeadSquared`, `WooCommerce`, `Shopify`, `WordPress`, `Asia/Kuwait` and every other tz
identifier, `Lynomia Commerce` (the literal webhook name in WooCommerce,
`ar/commerce/connect-woocommerce.md:74`).

**The two exceptions — and they are real:** `Salla` and `Zid` **are** localised by the product.
`app/javascript/dashboard/i18n/locale/ar/commerce.json:6-7` gives `"SALLA": "سلة"` and `"ZID": "زد"`, and those
are the companies' own Arabic brands. The corpus is split on this along the §3/§5 seam: `commerce/` uses Latin
(`ar/commerce/connect-salla.md:2` `ربط Salla`, `connect-zid.md:2` `ربط Zid`) while `troubleshooting/` uses Arabic
(`commerce-store-needs-reconnecting.md:3` `ووكومرس وسلة وزد وشوبيفاي`). **Recommend: `سلة` and `زد` in Arabic
prose, to match the UI, with the Latin form in parentheses on first use** — because `زد` alone is also the Arabic
imperative "increase", and `سلة` alone also means "basket" (and the product uses it that way at
`commerce.json:160,163`). `ووكومرس` and `شوبيفاي` must go: those companies have no Arabic brand and the Arabic UI
keeps them Latin.

**Machine-readable identifiers, never translated:** every WhatsApp error code (`131042`, `131049`, `131053`,
`131060`, `190`); every commerce error code (`INVALID_STORE_URL`, `AUTH_INVALID`, `STORE_UNAVAILABLE`, `TIMEOUT`,
`ORDER_CHANGED`, `NOT_APPLIED`, `REFUND_DECLINED`, `needs_reauth`, `missing_scope`); OAuth scopes (`write_orders`,
`whatsapp_business_messaging`, `whatsapp_business_management`); template categories and statuses (`UTILITY`,
`MARKETING`, `AUTHENTICATION`, `APPROVED`, `PENDING`, `REJECTED`, `PAUSED`, `DISABLED`); every webhook event name
(`conversation_created`, `message_created`, `contact_updated`, `inbox_updated`, `flow_webhook`,
`macro.executed`, `automation_event.<trigger>`); every payload field (`id`, `content`, `message_type`,
`changed_attributes`, `custom_attributes`, `source_id`); the three signature headers
`X-Chatwoot-Signature`, `X-Chatwoot-Timestamp`, `X-Chatwoot-Delivery` — and `ar/integrations/webhooks.md:90`
already says explicitly that these do not change with the installation's branding, which is exactly right;
`sha256=`, `HMAC-SHA256`, `POST`, `JSON`, `REST API`, `/wp-json`, `/wp-admin`, `localhost`, `myshopify.com`,
`https://`, HTTP status families `4xx` / `5xx`; language codes (`ar`, `en`); and the article slugs themselves.

**Also must stay Latin, for a different reason:** any UI string the Arabic product shows in English.
Today that includes `Account Health`, `Register Webhook`, `Webhook not configured`, `Custom Roles`,
`Create Automation`, `Permanent access token`, `Paste access token`, `WhatsApp Embedded Signup`,
`Connect with WhatsApp Business`, `Voice`, `Calls`, `Add SLA`, `WhatsApp campaigns`, `Create campaign`, and the
five custom-role permission labels. An Arabic article that translates these makes the reader unable to find the
control. **This list is a function of §3.7 and shrinks as the product is translated** — which is precisely why
the glossary cannot be frozen before the localisation decision is.

### 7.2 Mechanical conventions to freeze alongside the glossary

1. **Western digits** (`0-9`) everywhere. Fix the 16 Arabic-Indic digits in five files (§5.2).
2. **Arabic guillemets `«…»`** for all quoted UI strings and all quoted system messages; never Latin `"…"`.
   Fix the 14 Latin-quote files (§5.2).
3. **Arabic comma `،` and question mark `؟`** throughout — already the case.
4. **`الـ ` + space + Latin token** when the Arabic definite article precedes a Latin word
   (`الـ Webhook`, not `الـwebhook`). Fix 18 occurrences.
5. **No bidi control characters in source.** Direction is the renderer's job (§5.3). Remove the stray U+200F at
   `ar/commerce/connect-woocommerce.md:90`.
6. **One grammatical gender for the brand** — masculine, matching the 30-to-3 majority and the masculine head
   noun `تشات`. Fix the four feminine subject uses and `contact-lynomia-support.md:51` vs `:77,:110`.
7. **Link text must equal the target article's `title`** unless the link is deliberately an inline phrase; and an
   inline phrase must never introduce a second term for the same feature (§6.1).

---

## 8. What I did not check

- **I did not run anything.** No `rails`, no `rspec`, no request. Every claim is a file read.
- **I did not view a rendered Arabic page.** §5.3 is derived from the templates, the helper and the JavaScript;
  the visual consequences I list follow from the absence of `dir`, but I did not see them. Someone should load one
  Arabic article with JavaScript disabled and confirm.
- **The double-yield in `base_controller.rb:38-43`** (§5.3) is flagged, not established. It needs a request spec.
- **Five navigation-path segments are unverified** (§3.6) because the strings are not in the locale files.
- **I did not assess Arabic reading level or dialect fit.** The corpus is Modern Standard Arabic throughout, with
  Gulf-appropriate worked examples (Kuwait, Riyadh, Dubai, `Asia/Kuwait`, the Sunday-to-Thursday working week at
  `ar/workspace/set-up-an-inbox.md:52-54`). Whether MSA is the right register for a Gulf SME support audience is a
  product question I am not equipped to answer, and I am not raising it as a defect.
- **I did not check the Arabic changelog** (`custom/db/changelog`), which is outside my scope but runs through the
  same seeder and the same renderer, and therefore inherits §5.3.
- **Portal search behaviour in Arabic** (stemming, the definite article `ال`, transliteration synonyms) is agents
  077 and 078. §4.3 records the raw counts and claims nothing.
