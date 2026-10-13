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
