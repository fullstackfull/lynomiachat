# تقرير Phase 0 — الاكتشاف الكامل وتدقيق المعمارية
# Lynomia Chat — Full Project Discovery & Architecture Audit

**تاريخ التدقيق:** 2026-09-07
**نوع المرحلة:** READ → TRACE → UNDERSTAND → DOCUMENT → PLAN
**تعديلات على الكود:** لا يوجد (هذا المستند هو المُخرَج الوحيد)

**المستودعات المفحوصة:**

| # | المستودع | الفرع المفحوص | آخر Commit | عدد الـ Commits |
|---|---|---|---|---|
| 1 | `fullstackfull/lynomiachat` | `lynomia-custom` | `7bb7e5d8` — "Add Lynomia Chat customizations" (2026-08-03) | 914 |
| 2 | `fullstackfull/lynomia-chat-app98` | `main` | `2d83b30` — "final" | 3 |

---

## 1. Executive Summary — الملخص التنفيذي

### الخلاصة في ثلاث جمل

1. **`lynomiachat` هو نسخة (Fork) شبه نقية من Chatwoot 4.14.1 Enterprise Edition**، والتخصيص الفعلي الذي تم عليه هو **commit واحد فقط يمس 7 ملفات** (+341/−278 سطر)، معظمه تغييرات تجميلية في صفحة الدخول وشريط تنقل تسويقي، وليس تطويرًا منتجيًا.
2. **القدرات الـ Omnichannel الحقيقية موروثة بالكامل من Chatwoot** — لم يُضِف Lynomia أي قناة، ولم يُصلح أو يُعطّل أي قناة. القنوات موجودة بجودة Upstream عالية، لكن **لا يوجد في المستودع أي دليل على أن أيًّا منها مُهيّأ فعليًا (Configured)** بمفاتيح إنتاج.
3. **يوجد "بَاك-إند ثالث" غير موجود في أي من المستودعين** — `https://lynomia.com/api/*` — وهو المسؤول فعليًا عن التسجيل والخطط والاشتراكات والدفع. الطبقة التجارية (SaaS) الحقيقية لـ Lynomia **ليست داخل Chatwoot**، وتطبيق الموبايل يتحدث مع ثلاثة أنظمة في وقت واحد.

### الحكم النهائي على السؤال الأساسي

> **هل Lynomia Chat اليوم منصة Omnichannel فعلية؟**

**من ناحية القدرة (Capability): نعم.**
**من ناحية المنتج المُشغَّل (Product): لا — إنه اليوم "نشر Chatwoot مُعاد تسميته جزئيًا (Partial Re-brand)" مع طبقة دفع خارجية وتطبيق موبايل بدائي.**

### أخطر ثلاث نقاط اكتُشفت

| # | النقطة | الخطورة |
|---|---|---|
| 1 | تطبيق الموبايل يرسل **كلمة مرور المستخدم إلى نطاقين مختلفين** (`chat.lynomia.com` و `lynomia.com`) ويطبع **رمز الوصول (access_token) في سجلّات الجهاز** | P0 — أمني |
| 2 | صفحة الفوترة داخل Chatwoot أُفرِغت واستُبدلت بإعادة توجيه إلى `lynomia.com/admin/subscriptions/{accountId}` — أي **لا يوجد أي فرض حدود أو Feature Gating داخل المنتج نفسه** | P0 — تجاري |
| 3 | التعديل المكتوب عليه `# تعطيل الانقطاع الإجباري للأبد وتثبيت الاتصال دائماً` في `app/models/channel/whatsapp.rb` **لم يغيّر أي سطر منطقي** — التعليق يَعِد بسلوك غير مُنفَّذ | P1 — وهم وظيفي |

---

## 2. What Lynomia Chat Actually Is Today — ما هو Lynomia Chat فعليًا اليوم

### الوصف الدقيق

Lynomia Chat اليوم هو **ثلاثة أنظمة منفصلة** تتظاهر بأنها منتج واحد:

```
┌────────────────────────────────────────────────────────────────────┐
│  النظام (أ) — chat.lynomia.com                                     │
│  Chatwoot 4.14.1 EE  (مستودع fullstackfull/lynomiachat)            │
│  • كل منطق المحادثات، القنوات، الوكلاء، التقارير                    │
│  • Re-brand جزئي: شعار + Navbar + خلفية صفحة الدخول                 │
└────────────────────────────────────────────────────────────────────┘
                 ▲                              ▲
                 │ /api/v1/... (api_access_token)│ /auth/sign_in
                 │ /cable (ActionCable)          │
┌────────────────┴──────────────┐   ┌───────────┴────────────────────┐
│  النظام (ب) — تطبيق Flutter   │   │  النظام (ج) — lynomia.com       │
│  lynomia-chat-app98           │──▶│  ⚠️ غير موجود في أي مستودع       │
│  35 ملف Dart                  │   │  • /api/login                   │
│  • تطبيق وكيل (Agent) بدائي   │   │  • /api/register/google         │
│  • + شاشات دفع واشتراك        │   │  • /api/plans/chat              │
└───────────────────────────────┘   │  • /api/chat/mobile-checkout    │
                                     │  • /admin/subscriptions/{id}    │
                                     └─────────────────────────────────┘
```

### الدليل

- `app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue:8-10` → إعادة توجيه إلى `https://lynomia.com/admin/subscriptions/${accountId}`
- `lynomia-chat-app98/lib/shared/network/payment_api_service.dart:26,84,135,185` → أربع نقاط نهاية على `lynomia.com`
- `lynomia-chat-app98/lib/shared/network/chatwoot_api_service.dart:1045-1090` → `_loginToLynomia()` يُستدعى بعد كل تسجيل دخول ناجح على Chatwoot

**الاستنتاج:** النظام (ج) هو "المخ التجاري" للمنتج، وهو **خارج نطاق هذا التدقيق لأنه غير مُتاح**. أي قرار معماري مستقبلي لا يمكن اتخاذه بأمان دون فحصه.

---

## 3. Repository Relationship — العلاقة بين المستودعين

| البُعد | `lynomiachat` | `lynomia-chat-app98` |
|---|---|---|
| النوع | Rails 8 / Vue 3 (Chatwoot Fork) | Flutter 3.x |
| الحجم | ~914 commit، 87 جدول، 733 spec | 3 commits، 35 ملف Dart، 1 widget test فارغ |
| العلاقة | **الخادم** | **عميل REST + ActionCable** |
| العقد المشترك | `/api/v1/accounts/...` + `/auth/sign_in` + `/cable` | يستهلكها |
| المشاركة في الكود | **صفر** — لا SDK مشترك، لا OpenAPI مُولَّد، لا Types مشتركة | — |
| الاعتماد الثالث | يوجّه الفوترة إلى `lynomia.com` | يستدعي `lynomia.com` مباشرة |

**ملاحظة حاسمة:** المستودعان **غير متزامنين تعاقديًا**. لا يوجد ملف مواصفات API مشترك، رغم أن `lynomiachat` يحتوي على مجلد `swagger/` كامل (موروث من Chatwoot) لم يستخدمه تطبيق الموبايل إطلاقًا.

---

## 4. Architecture Map — خريطة المعمارية

### 4.1 معمارية الخادم (موروثة من Chatwoot)

```
                       ┌──────────────────────┐
   Internet ──────────▶│  Nginx (deployment/  │
                       │  nginx_chatwoot.conf)│
                       └──────────┬───────────┘
                                  │
            ┌─────────────────────┼─────────────────────┐
            ▼                     ▼                     ▼
    ┌───────────────┐    ┌────────────────┐    ┌────────────────┐
    │ Rails / Puma  │    │  ActionCable   │    │ Sidekiq Worker │
    │ (web)         │    │  (/cable)      │    │ (Procfile)     │
    └───────┬───────┘    └────────┬───────┘    └────────┬───────┘
            │                     │                     │
            ├─────────────────────┴─────────────────────┤
            ▼                                           ▼
    ┌───────────────┐                          ┌────────────────┐
    │  PostgreSQL   │                          │     Redis      │
    │  87 جدول      │                          │ (Cable/Queue/  │
    │  + pgvector   │                          │  Cache/Alfred) │
    └───────────────┘                          └────────────────┘
            │
            ▼
    ┌──────────────────────────────────────────────────┐
    │  ActiveStorage → local | S3 | Azure | GCS         │
    └──────────────────────────────────────────────────┘
```

### 4.2 طبقات الكود

| الطبقة | المسار | الدور |
|---|---|---|
| Controllers | `app/controllers/api/v1/accounts/**` | REST API (مُغلَّف بـ `Current.account`) |
| Webhook Controllers | `app/controllers/webhooks/*` | استقبال من المزودين |
| Builders | `app/builders/**` | إنشاء الكيانات (Message, Contact, Conversation) |
| Services | `app/services/**` | منطق القنوات (`Whatsapp::`, `Instagram::`, `Facebook::`) |
| Jobs | `app/jobs/**` | معالجة غير متزامنة (Sidekiq) |
| Listeners / Events | `app/listeners/**`, `config/initializers/event_handlers.rb` | Pub/Sub داخلي |
| Dispatchers | `app/dispatchers/**` | توزيع الأحداث (Async/Sync) |
| Enterprise Overlay | `enterprise/**` | `prepend_mod_with` عبر `01_inject_enterprise_edition_module.rb` |

**ملاحظة:** مجلد `enterprise/` **موجود** ⇒ `ChatwootApp.enterprise?` تُرجع `true` (`lib/chatwoot_app.rb:16-19`). أي أن النشر يعمل بنسخة Enterprise، وهذا له تبعات ترخيصية يجب مراجعتها قانونيًا.

### 4.3 المعمارية الفعلية للمنتج (بما فيها النظام الثالث)

راجع المخطط في القسم 2. النقطة المعمارية الأخطر: **مصدر الحقيقة للهوية (Identity) مُكرَّر** — المستخدم موجود في Chatwoot (`users` table) و في `lynomia.com` في آنٍ واحد، ولا يوجد SSO حقيقي بينهما، بل **إعادة إرسال كلمة المرور نفسها إلى النظامين**.

---

## 5. Technology Stack — حزمة التقنيات

### 5.1 الخادم (`lynomiachat`)

| المكوّن | الإصدار / التفصيل | المصدر |
|---|---|---|
| Ruby | 3.4.4 | `.ruby-version` |
| Rails | 8.x | `Gemfile.lock` |
| Node | 24.x | `package.json:154` |
| pnpm | 10.x | `package.json:155` |
| Frontend | Vue 3 + Vite + Pinia/Vuex + Tailwind | `package.json`, `tailwind.config.js` |
| DB | PostgreSQL (+ `pgvector` لـ Captain AI) | `db/schema.rb` |
| Queue | Sidekiq + Redis | `Procfile` |
| Realtime | ActionCable على Redis | `config/cable.yml` |
| Search | Searchkick / Elasticsearch (اختياري) | `config/initializers/searchkick.rb` |
| Rate Limit | `rack-attack` | `config/initializers/rack_attack.rb` |
| APM | New Relic / Datadog / Elastic APM / Scout (كلها اختيارية) | `config/*.yml` |
| Errors | Sentry (اختياري) | `Gemfile` |

**مكتبات القنوات:**
`facebook-messenger`, `koala` (Meta Graph), `line-bot-api`, `twilio-ruby`, `twitty` (Twitter), `fcm` (Push), `stripe`.

### 5.2 الموبايل (`lynomia-chat-app98`)

| المكوّن | الإصدار |
|---|---|
| Flutter SDK | `>=3.0.0 <4.0.0` |
| State Mgmt | `flutter_bloc` ^9.1.1 (Cubit) |
| HTTP | `dio` ^4.0.6 ⚠️ (الإصدار 5.x هو الحالي) |
| Realtime | `web_socket_channel` ^2.4.0 (ActionCable يدوي، بدون مكتبة) |
| Push | `firebase_messaging` ^15.2.10 + `flutter_local_notifications` ^18 |
| Auth | `firebase_auth`, `google_sign_in` ^6.2.1 |
| Payments | `flutter_stripe` ^11 + Google Play Billing مخصّص |
| SDK غريب | `chatwoot_client_sdk` (بدون قيد إصدار) — **SDK الودجت للعملاء، لا علاقة له بتطبيق الوكيل** |

**علامة إنذار:** وجود `chatwoot_client_sdk` (SDK محادثة العميل) في تطبيق يُفترض أنه للوكلاء يؤكد أن التطبيق **بدأ كتطبيق عميل ثم تحوّل إلى تطبيق وكيل دون تنظيف**.

---

## 6. Chatwoot Upstream Analysis — تحليل الأصل من Chatwoot

### 6.1 هل هو Fork من Chatwoot؟

**نعم، وبشكل قاطع.**

| الدليل | القيمة |
|---|---|
| `VERSION_CW` | `4.14.1` |
| آخر Commit من Upstream | `d58b6a6c` — `Merge branch 'release/4.14.1'` |
| تاريخ آخر مزامنة | **2026-05-29** |
| Commit التخصيص الوحيد | `7bb7e5d8` — 2026-08-03 |
| الفجوة الزمنية | ~66 يومًا بين آخر Upstream وأول تخصيص |
| ملفات Chatwoot الأصلية المتبقية | `LICENSE`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, `crowdin.yml`, `.github/workflows/*` (16 workflow) — **جميعها بلا تعديل** |

### 6.2 مقدار التعديل

```
git diff d58b6a6c..7bb7e5d8 --stat
 7 files changed, 341 insertions(+), 278 deletions(-)
```

**نسبة التخصيص التقديرية: أقل من 0.05% من قاعدة الكود.**

هذا رقم بالغ الأهمية: المشروع عمليًا **Chatwoot، وليس مشتقًا منه**.

### 6.3 ما هو أصلي من Chatwoot (أي: كل شيء تقريبًا)

كل ما يلي **موروث بالكامل وغير معدّل**:
كل القنوات · كل الـ Webhooks · كل الـ Services · كل الـ Models · كل الـ Migrations (135) · كل الـ Specs (733 Ruby + 349 JS) · Enterprise overlay بالكامل (Captain AI، SLA، Custom Roles، SAML، Voice، Audit Logs) · Super Admin (Administrate) · Sidekiq jobs · Reports · Campaigns · Automations · Macros · Help Center · CSAT · Contacts/CRM · Webhooks API · Platform API.

### 6.4 ما أُضيف خصيصًا لـ Lynomia

| الملف | الإضافة | التقييم |
|---|---|---|
| `app/javascript/dashboard/components/Navbar.vue` | **ملف جديد** — 286 سطر، شريط تنقل تسويقي | يخالف `CLAUDE.md` (CSS مخصّص بدل Tailwind)، روابط `lynomia.com` مضمّنة بالكود، شعار من CDN خارجي |
| `config/initializers/devise.rb:251-257` | تسجيل `google_oauth2` كمزود Devise OmniAuth | **مُكرَّر** — `config/initializers/omniauth.rb:5-9` يسجّله أصلًا عبر `OmniAuth::Builder` |

### 6.5 ما تم تعديله

| الملف | التعديل | الأثر |
|---|---|---|
| `app/javascript/v3/views/login/Index.vue` | شعار مضمّن بالكود + عنوان إنجليزي ثابت + `<style>` **غير مُنطاق (unscoped)** | كسر i18n + تسريب CSS عالمي (تفصيل في §26) |
| `app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue` | **267 سطر → 15 سطر** — حُذفت كل واجهة الفوترة | فقدان كامل لعرض الخطة/الاستخدام/الحدود داخل المنتج |
| `.../billing/billing.routes.js` | حذف `installationTypes: [INSTALLATION_TYPES.CLOUD]` من مستويين | فتح مسار الفوترة على النشر الذاتي |
| `app/services/whatsapp/channel_creation_service.rb:69-71` | اسم الـ Inbox = رقم الهاتف بدل `"{business_name} WhatsApp"` | تغيير سلوكي مقصود، مقبول |
| `app/models/channel/whatsapp.rb:142-143` | مسافة بادئة على `end` + تعليق عربي | **صفر تغيير منطقي** (تفصيل في §28) |

### 6.6 ما تم تعطيله أو حذفه

**لا شيء على مستوى الخادم.** لم تُحذف أي قناة ولا أي خدمة ولا أي Migration. الحذف الوحيد هو واجهة الفوترة في الـ Frontend.

### 6.7 هل ما زال المشروع قابلًا للاستفادة من تحديثات Upstream؟

**نعم — وبدرجة ممتازة نادرة.**

| العامل | التقييم |
|---|---|
| عدد ملفات التعارض المحتملة | **7 فقط** |
| هل هناك Fork داخلي لملفات جوهرية؟ | **لا** |
| هل عُدّلت الـ Migrations؟ | **لا** |
| هل عُدّل `enterprise/`؟ | **لا** |
| صعوبة `git merge upstream/develop` | **منخفضة جدًا** |

### 6.8 خطر تحديث Chatwoot مستقبلًا

| الملف | احتمال التعارض | السبب |
|---|---|---|
| `app/javascript/v3/views/login/Index.vue` | **عالٍ** | ملف يتغيّر كثيرًا في Upstream (MFA، SSO، Branding) |
| `.../billing/Index.vue` | **عالٍ جدًا** | أُفرِغ بالكامل ⇒ أي merge سيُعيد 267 سطرًا أو يُنتج تعارضًا ضخمًا |
| `.../billing.routes.js` | متوسط | |
| `config/initializers/devise.rb` | متوسط | |
| `app/services/whatsapp/channel_creation_service.rb` | متوسط | ملف نشِط في Upstream |
| `app/models/channel/whatsapp.rb` | **منخفض جدًا** | التعديل تجميلي بالكامل ⇒ **يُنصح بالتراجع عنه فورًا لإزالة التعارض مجانًا** |
| `Navbar.vue` | **صفر** | ملف جديد |

> **التوصية (لا تُنفَّذ الآن):** تحويل التخصيصات الـ 5 المتبقية إلى **Chatwoot Custom Branding + `custom/` overlay** (المدعوم أصلًا في `lib/chatwoot_app.rb:29-31`) بدل التعديل المباشر على ملفات Upstream. هذا يُنزل عدد ملفات التعارض من 6 إلى ~1.

---

## 7. Lynomia Customizations — جرد التخصيصات الكامل

| # | الملف | النوع | الأسطر | الغرض المُعلن | الغرض المُنفَّذ فعليًا |
|---|---|---|---|---|---|
| 1 | `dashboard/components/Navbar.vue` | جديد | +286 | شريط تنقل مؤسسي | شريط تنقل يظهر **فقط في صفحة الدخول** |
| 2 | `v3/views/login/Index.vue` | تعديل | +50/−13 | Re-brand | شعار ثابت + CSS عالمي + كسر i18n |
| 3 | `.../billing/Index.vue` | استبدال | +15/−267 | ربط الفوترة الخارجية | Redirect فوري خارج المنتج |
| 4 | `.../billing/billing.routes.js` | تعديل | −2 | إتاحة الفوترة للنشر الذاتي | + import غير مستخدم (كسر Lint) |
| 5 | `services/whatsapp/channel_creation_service.rb` | تعديل | +1/−2 | تسمية الـ Inbox برقم الهاتف | ✅ يعمل كما هو مُعلن |
| 6 | `models/channel/whatsapp.rb` | تعديل | +2/−1 | "تثبيت الاتصال دائمًا" | ❌ **لا شيء** |
| 7 | `config/initializers/devise.rb` | تعديل | +7/−1 | تفعيل Google OAuth | ⚠️ تسجيل مُكرَّر |

**ملاحظة على جودة الـ Commit:** المؤلف هو `root <root@server2.lynomia.com>` — أي أن التعديلات كُتبت **مباشرة على خادم الإنتاج**، لا في بيئة تطوير. هذا مؤشر عملياتي خطير بحد ذاته (راجع §24).

---

## 8. Backend Analysis — تحليل الخادم

### 8.1 الجاهزية العامة

الخادم هو **Chatwoot 4.14.1 EE سليم**. جودته عالية: 733 spec، معمارية Service/Builder/Listener نظيفة، Enterprise overlay مفصول بـ `prepend_mod_with`.

### 8.2 المكونات المتحققة

| المكوّن | الحالة | الدليل |
|---|---|---|
| Multi-tenancy | ✅ `Current.account` + `account_id` على كل الجداول | `app/controllers/api/v1/accounts/**` |
| Authorization | ✅ Pundit Policies + Custom Roles (EE) | `app/policies/**`, `enterprise/app/policies/**` |
| Background Jobs | ✅ Sidekiq، صفوف متعددة الأولوية | `Procfile`, `config/sidekiq.yml` |
| Realtime | ✅ ActionCable + `RoomChannel` + `pubsub_token` | `app/channels/room_channel.rb` |
| Rate Limiting | ✅ `rack-attack` — حدود على login/reset/MFA/super_admin | `config/initializers/rack_attack.rb:70-145` |
| Webhook Signature | ✅ Meta (`MetaTokenVerifyConcern`)، TikTok (HMAC-SHA256)، Shopify (HMAC-Base64) | `app/controllers/webhooks/*` |
| Error Handling | ✅ `lib/custom_exceptions/` + `custom_error_codes.rb` | |
| Logging | ✅ `lograge` + `filter_parameter_logging` | `config/initializers/lograge.rb` |
| Push (FCM v1) | ✅ Service Account + OAuth token caching | `app/services/notification/fcm_service.rb` |
| Audit Log | ✅ (EE) `audited` gem | `config/initializers/audited.rb` |

### 8.3 الحدود والاستخدام (Limits)

- **OSS:** `app/models/account.rb:149-154` → `agents: 100_000`, `inboxes: 100_000` (أي: **بلا حدود عمليًا**)
- **EE:** `enterprise/app/models/enterprise/account/plan_usage_and_limits.rb:7-16` → حدود حقيقية من `InstallationConfig['CHATWOOT_CLOUD_PLANS']`

**النتيجة:** بما أن `enterprise/` موجود، آلية الحدود **متاحة** لكن **غير مُهيّأة** (لا يوجد أي دليل في المستودع على تعبئة `CHATWOOT_CLOUD_PLANS`). عمليًا: **لا حدود.**

---

## 9. Web Frontend Analysis — تحليل واجهة الويب

### 9.1 البنية

Vue 3 + `<script setup>` + Vite + Tailwind. مُقسَّم إلى:
- `app/javascript/dashboard/` — لوحة الوكيل (قيد الإهلاك تدريجيًا حسب `CLAUDE.md`)
- `app/javascript/next/` + `components-next/` — الجيل الجديد (فقاعات الرسائل)
- `app/javascript/v3/` — صفحات المصادقة
- `app/javascript/widget/` — ودجت الموقع
- `app/javascript/portal/` — مركز المساعدة

### 9.2 القنوات المعروضة في واجهة إنشاء Inbox

`app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue:23-105`

**ثابتة دائمًا:** Website, Facebook, WhatsApp, SMS, Email, API, Telegram, LINE, Instagram, Voice, WhatsApp Call
**مشروطة:** TikTok (فقط إذا `window.chatwootConfig.tiktokAppId` موجود)
**غائبة تمامًا من الواجهة:** **Twitter/X** — رغم وجود `Channel::TwitterProfile` و `Twitter.vue` في الكود

### 9.3 ملفات مكوّنات القنوات الموجودة

```
360DialogWhatsapp.vue  Api.vue      BandwidthSms.vue   CloudWhatsapp.vue
Email.vue              Facebook.vue Instagram.vue      Line.vue
Sms.vue                Telegram.vue Tiktok.vue         Twilio.vue
Twitter.vue            Voice.vue    Website.vue        Whatsapp.vue
WhatsappCall.vue       WhatsappEmbeddedSignup.vue
```

### 9.4 مشاكل الواجهة الناتجة عن تخصيصات Lynomia

راجع §26 (UX/UI) و §28 (Bugs).

---

## 10. Mobile App Analysis — تحليل تطبيق الموبايل

### 10.1 الهوية الحقيقية للتطبيق

| السؤال | الجواب |
|---|---|
| هل هو تطبيق وكيل (Agent) أم عميل (Customer)؟ | **تطبيق وكيل** — يسجّل الدخول عبر `/auth/sign_in` ويستخدم `api_access_token` |
| لكن هل يحتوي كود عميل؟ | **نعم** — نصف `chatwoot_api_service.dart` هو كود `public/api/v1/inboxes/...` (واجهة الودجت) |
| هل الكود القديم محذوف؟ | **لا** — مُعلَّق بالكامل. من 2125 سطر في الملف، **الأسطر 1–345 مُعلَّقة بالكامل** |
| هل يوجد اختبارات؟ | **لا** — `test/widget_test.dart` فقط (قالب Flutter الافتراضي) |

### 10.2 تتبع التدفق الفعلي

```
SplashScreen
   ↓ (CacheHelper: is_logged_in?)
LoginScreen ──▶ POST chat.lynomia.com/auth/sign_in
                   ↓ {access_token, account_id, pubsub_token, id}
                POST lynomia.com/api/login   ← ⚠️ نفس كلمة المرور مرة ثانية
                   ↓ {access_token} (lynomia_token للدفع)
                POST /api/v1/notification_subscriptions (FCM)
   ↓
InboxSelectionScreen ──▶ GET /api/v1/accounts/{id}/inboxes
   ↓
ConversationsListScreen ──▶ GET /api/v1/accounts/{id}/conversations?status=open[&inbox_id=]
   ↓
ChatScreen ──▶ GET  /api/v1/accounts/{id}/conversations/{cid}/messages
           ──▶ POST /api/v1/accounts/{id}/conversations/{cid}/messages
           ──▶ WSS  /cable  → subscribe RoomChannel {pubsub_token, account_id, user_id}
```

### 10.3 واجهة الـ API الفعلية للتطبيق (34 دالة)

**Chatwoot Agent API:** `login`, `registerWithGoogle`, `registerWithApple`, `fetchUserProfile`, `fetchInboxes`, `fetchConversations`, `fetchMessagesAdminApi`, `sendMessageAdminApi`, `sendMessageWithAttachment`, `deleteMessageAdminApi`, `createConversationAdminApi`, `createContactAdminApi`, `searchContactsAdminApi`, `fetchContactDetails`, `updateContactName`, `updateLastSeen`, `registerFcmToken`
**Chatwoot Public/Widget API (ميت):** `createContact`, `getOrCreateConversation`, `sendMessage`, `getMessages`, `connectWebSocket`
**Lynomia API:** `_loginToLynomia`, `checkSubscription`, `fetchTerms`, + 4 دوال في `payment_api_service.dart`

### 10.4 هل التطبيق Channel-agnostic؟

**على مستوى الـ API: نعم.** يجلب كل الـ Inboxes ويعرض كل المحادثات بغض النظر عن نوع القناة.
**على مستوى العرض: لا — ومكسور.**

`lib/modules/inbox_selection/inbox_selection_screen.dart:279-345` يقارن:
```dart
switch (channelType?.toLowerCase()) {
  case 'whatsapp': ...
  case 'facebook': ...
```
لكن الخادم يُرجع `"Channel::Whatsapp"` (`app/views/api/v1/models/_inbox.json.jbuilder:5`).
`"Channel::Whatsapp".toLowerCase()` = `"channel::whatsapp"` ⇒ **لا يطابق أي case** ⇒ كل الـ Inboxes تعرض الأيقونة الافتراضية `Icons.inbox` واللون الرمادي والاسم `"Channel::Whatsapp"` الخام.

**⇒ التطبيق لا يميّز القنوات بصريًا إطلاقًا في الإنتاج.** (P2، دليل قاطع)

### 10.5 فجوة الميزات: Web مقابل Mobile

| الميزة | Web | Mobile | الحالة |
|---|---|---|---|
| قائمة المحادثات | ✅ | ✅ | موجود |
| إرسال/استقبال رسائل | ✅ | ✅ | موجود |
| Realtime (ActionCable) | ✅ | ✅ | موجود (مع تحفظات §18) |
| المرفقات (رفع) | ✅ | ✅ | موجود |
| الصوت (تسجيل/تشغيل) | ✅ | ❌ | **مفقود** |
| مؤشر الكتابة (Typing) | ✅ | ✅ جزئي | `typing_status` مُرسل |
| حذف رسالة | ✅ | ✅ | موجود |
| **تعيين وكيل (Assignment)** | ✅ | ❌ | **مفقود** |
| **الفرق (Teams)** | ✅ | ❌ | **مفقود** |
| **التصنيفات (Labels)** | ✅ | ❌ | **مفقود** |
| **تغيير الحالة (open/resolved/pending/snoozed)** | ✅ | ❌ | **مفقود** — يقرأ `status` فقط كفلتر |
| **الردود الجاهزة (Canned Responses)** | ✅ | ❌ | **مفقود** |
| **الملاحظات الخاصة (Private Notes)** | ✅ | ❌ | **مفقود** |
| **الإشارات (Mentions)** | ✅ | ❌ | **مفقود** |
| **عدّادات غير المقروء** | ✅ | ❌ | **مفقود** |
| **فلاتر متقدمة / بحث** | ✅ | ❌ | فلتر `status` + `inbox_id` فقط |
| **قوالب WhatsApp** | ✅ | ❌ | **مفقود** — حرج لنافذة الـ 24 ساعة |
| **Custom Attributes / CRM** | ✅ | ❌ | **مفقود** |
| **Macros / Automations** | ✅ | ❌ | **مفقود** |
| **التقارير** | ✅ | ❌ | **مفقود** |
| Push Notifications | ✅ | ✅ | موجود (FCM) |
| **الدفع / الاشتراكات** | ➖ (redirect) | ✅ | **موجود في الموبايل فقط** |

**الخلاصة:** التطبيق يغطّي تقديريًا **~20% من قدرات وكيل Chatwoot**. هو "عارض محادثات + مُرسل رسائل + بوابة دفع"، وليس تطبيق وكيل تشغيلي.

### 10.6 جاهزية الإصدار

| البند | الحالة |
|---|---|
| `applicationId` / Bundle ID | `com.Lynomia.Lynomia_chat` ✅ متطابق بين Android و iOS |
| توقيع Android Release | ✅ مُعدّ عبر `keystoreProperties` (`android/app/build.gradle.kts:76-83`) — الملف نفسه غير مُتتبَّع ✅ |
| Firebase | ✅ `google-services.json` (مشروع `lynomia-chat-fc5e0`) |
| الإصدار | `1.0.0+7` |
| اسم الحزمة في `pubspec.yaml` | `chat` — الوصف لا يزال `"A new Flutter project."` ❌ |
| README | **قالب Flutter الافتراضي غير معدّل** ❌ |
| Sign in with Apple | ❌ **مكسور** — `lib/layout/cubit/cubit.dart:1408` يشير إلى `https://your-backend.com/callbacks/sign_in_with_apple` مع تعليق `// ← من زميلك` |

---

## 11. API Architecture — معمارية الـ API

### 11.1 الخريطة المطلوبة

```
┌──────────────────────────┐
│  Flutter Mobile App      │
└────────────┬─────────────┘
             │
   ┌─────────┴──────────────────────────────┐
   │                                        │
   ▼                                        ▼
┌────────────────────────┐      ┌────────────────────────┐
│ chat.lynomia.com       │      │ lynomia.com            │
│ (Chatwoot)             │      │ (نظام مجهول)            │
│                        │      │  /api/login            │
│ POST /auth/sign_in     │      │  /api/register/google  │
│ GET  /api/v1/profile   │      │  /api/plans/chat       │
│ GET  .../inboxes       │      │  /api/chat/subscription│
│ GET  .../conversations │      │  /api/chat/mobile-     │
│ GET/POST .../messages  │      │       checkout         │
│ POST .../update_last_  │      │  /api/verify-google-   │
│      seen              │      │       play-purchase    │
│ CRUD .../contacts      │      │  /api/my/payment/chat  │
│ POST /api/v1/          │      │  /api/term/chat        │
│   notification_        │      │  /api/auth/apple/signup│
│   subscriptions        │      └────────────────────────┘
│ WSS  /cable            │
└───────────┬────────────┘
            ▼
┌────────────────────────────────────────────┐
│  Core Services (Rails)                     │
│  Builders → Services → Jobs → Listeners    │
└───────────┬────────────────────────────────┘
            ▼
┌────────────────────────────────────────────┐
│  Channel Adapters                          │
│  Whatsapp::Providers::{WhatsappCloud,       │
│                        Whatsapp360Dialog}   │
│  Instagram::*  Facebook::*  Telegram  LINE  │
│  Twilio  Bandwidth  Email(IMAP/SMTP/OAuth)  │
└───────────┬────────────────────────────────┘
            ▼
┌────────────────────────────────────────────┐
│  External Provider APIs                     │
│  graph.facebook.com · 360dialog · Telegram  │
│  api.line.me · Twilio · TikTok · SMTP/IMAP  │
└────────────────────────────────────────────┘
```

### 11.2 التدقيق التفصيلي

| البند | الحالة | الدليل |
|---|---|---|
| **Hardcoded endpoints** | ❌ **الكل مضمّن بالكود** | `constants.dart:2` = `https://chat.lynomia.com`؛ `dio_helper.dart` (النسخة الحية) baseUrl مضمّن؛ 8 روابط `lynomia.com` مضمّنة نصًا |
| **Deprecated endpoints** | ❌ نعم | كل مسارات `/public/api/v1/inboxes/...` في التطبيق ميتة وظيفيًا (بقايا الودجت) |
| **Duplicated APIs** | ❌ نعم | `sendMessage()` (public) و `sendMessageAdminApi()`؛ `connectWebSocket()` و `connectWebSocketAdmin()`؛ `getMessages()` و `fetchMessagesAdminApi()` |
| **Authentication** | ⚠️ مزدوج | `api_access_token` **و** `Authorization: Bearer` يُرسلان معًا (`chatwoot_api_service.dart:1023-1024`) — Chatwoot يستخدم الأول فقط |
| **Token handling** | ❌ **غير آمن** | يُخزَّن في `SharedPreferences` (نص صريح، غير مشفّر) بدل `flutter_secure_storage` |
| **Token logging** | ❌ **حرج** | `print('✅ Access token saved: $_authToken')` (سطر 1025) — الرمز يُطبع في logcat/Console |
| **Pagination** | ❌ **غير موجود** | `fetchConversations` لا يمرّر `page`؛ `fetchMessagesAdminApi` لا يمرّر `before` |
| **Caching** | ❌ غير موجود | لا HTTP cache، لا تخزين محلي للمحادثات |
| **Error handling** | ⚠️ ضعيف | `validateStatus: (status) => true` (سطر 399) يُعطّل كل أخطاء Dio ⇒ كل خطأ HTTP يُعامَل كنجاح حتى يُفحص يدويًا؛ ورسائل الخطأ عربية ثابتة غير مترجمة |
| **Retries** | ❌ غير موجود | لا يوجد أي منطق إعادة محاولة على REST |
| **Rate limits** | ❌ غير مُعالَج | لا يوجد تعامل مع 429 من `rack-attack` |
| **Realtime** | ⚠️ يدوي | ActionCable مُنفّذ يدويًا عبر `web_socket_channel`؛ يعالج `ping`/`welcome`/`confirm_subscription`/`reject_subscription` ✅؛ إعادة اتصال بعد 5 ثوانٍ ثابتة (بلا backoff) ⚠️ |
| **Tenant fallback** | ❌ **خطير** | `accountId ?? _accountId ?? 4` يتكرّر 4 مرات (أسطر 686، 709، 730، 1173) — رقم حساب مضمّن كاحتياطي |

---

## 12. Database Architecture — معمارية قاعدة البيانات

### 12.1 الأرقام

- **87 جدولًا** (`db/schema.rb`)
- **135 Migration** — آخرها `20260525093000_change_captain_document_external_link_to_text.rb`
- **صفر migration من Lynomia**

### 12.2 خريطة العلاقات الأساسية

```
                         ┌─────────────┐
                         │   Account   │  ← جذر العزل متعدد المستأجرين
                         └──────┬──────┘
                                │ 1:N على كل شيء تقريبًا
    ┌──────────┬──────────┬─────┴─────┬──────────┬───────────┐
    ▼          ▼          ▼           ▼          ▼           ▼
┌────────┐ ┌───────┐ ┌────────┐ ┌─────────┐ ┌────────┐ ┌──────────┐
│AccountUser│Team  │ │ Inbox  │ │ Contact │ │ Label  │ │Automation│
│(role:   │ │       │ │        │ │         │ │        │ │  Rule    │
│ agent|  │ └───┬───┘ └───┬────┘ └────┬────┘ └────────┘ └──────────┘
│ admin)  │     │         │           │
└────┬────┘     │         │           │
     │          │         │ 1:1 polymorphic
     ▼          │         ▼
┌────────┐      │  ┌──────────────────────────────────────┐
│  User  │      │  │  Channel::{Whatsapp | FacebookPage |  │
└────────┘      │  │   Instagram | Telegram | Line | Sms | │
                │  │   TwilioSms | Email | WebWidget |     │
                │  │   Api | Tiktok | TwitterProfile}      │
                │  └──────────────────────────────────────┘
                │         │
                │         │  ┌──────────────┐
                │         └─▶│ InboxMember  │──▶ User
                │            └──────────────┘
                ▼
         ┌──────────────┐        ┌──────────────┐
         │ ContactInbox │◀───────│   Contact    │
         │ (source_id)  │        └──────┬───────┘
         └──────┬───────┘               │
                │                        │
                ▼                        ▼
         ┌──────────────────────────────────────┐
         │           Conversation               │
         │  account_id, inbox_id, contact_id,   │
         │  assignee_id, team_id, status,       │
         │  display_id, priority, ...           │
         └──────┬───────────────────────────────┘
                │ 1:N
                ▼
         ┌──────────────┐      ┌─────────────────┐
         │   Message    │─1:N─▶│   Attachment    │
         │ message_type │      │ (ActiveStorage) │
         │ content_type │      └─────────────────┘
         │ source_id    │
         │ status       │
         └──────────────┘

Enterprise Overlay:
  Account ──▶ SlaPolicy ──▶ AppliedSla ──▶ SlaEvent
  Account ──▶ CustomRole ──▶ AccountUser.custom_role_id
  Account ──▶ AgentCapacityPolicy ──▶ InboxCapacityLimit
  Account ──▶ Captain::{Assistant, Document, Scenario} (pgvector)
  Account ──▶ AccountSamlSettings

Integrations:
  Account ──▶ Integrations::Hook ──▶ Integrations::App
  Account ──▶ Webhook (account/inbox scoped, + secret)
  Account ──▶ Notification ──▶ NotificationSubscription (fcm/webpush)
```

### 12.3 المشاكل المُكتشَفة

| المشكلة | التفصيل | الخطورة |
|---|---|---|
| **قيد فريد عالمي على رقم WhatsApp** | `index_channel_whatsapp_on_phone_number (phone_number) UNIQUE` — **بلا `account_id`** ⇒ رقم WhatsApp واحد لا يمكن أن يوجد في حسابين. في SaaS متعدد المستأجرين هذا يعني: إذا سجّل عميل رقمًا وغادر، **لا يستطيع عميل آخر استخدامه أبدًا** حتى لو كان يملكه. كما أن `Channel::Whatsapp.find_by(phone_number:)` في `channel_creation_service.rb:29` يبحث **عبر كل الحسابات** ⇒ رسالة الخطأ تُسرّب وجود الرقم لدى مستأجر آخر | **P1** |
| **`accountId` احتياطي = 4 في الموبايل** | ليس مشكلة DB بل مشكلة عزل مستأجرين من جهة العميل | **P1** |
| **Migrations لإعادة استخدام أعلام** | `20260508000000_repurpose_channel_twitter_flag_for_conversation_unread_counts.rb` — دليل على إهلاك Twitter رسميًا في Upstream | معلوماتي |
| **Orphan relations** | لم يُعثر على علاقات يتيمة — Chatwoot يستخدم `dependent: :destroy_async` بانتظام | ✅ |
| **Duplicated tables** | لا يوجد | ✅ |
| **Missing indexes** | فهارس Upstream شاملة؛ لم يُرصد نقص | ✅ |
| **Scalability risks** | `messages` و `conversations` تنمو بلا حدود؛ Chatwoot لا يوفّر تقسيمًا (partitioning) أو أرشفة تلقائية. عند عشرات ملايين الرسائل ستحتاج استراتيجية أرشفة | **P2** |

---

## 13. Omnichannel Matrix — مصفوفة القنوات

### مفتاح القراءة
- ✅ = موجود ومكتمل في الكود (موروث من Chatwoot، جودة إنتاجية)
- ⚠️ = موجود لكن مشروط/ناقص
- ❌ = غير موجود
- **❓ = يتطلب تحقق تشغيلي على الخادم — لا يمكن إثباته من المستودع**

| Channel | موجود بالكود | إعداد Backend | UI | Webhook | إرسال | استقبال | Mobile | Production Ready |
|---|---|---|---|---|---|---|---|---|
| **WhatsApp (Meta Cloud API)** | ✅ | ✅ + Embedded Signup | ✅ (3 شاشات) | ✅ `/webhooks/whatsapp/:phone` + توقيع | ✅ نص/وسائط/قوالب/تفاعلي | ✅ + حالات التسليم | ⚠️ عام | ❓ |
| **WhatsApp (360dialog)** | ✅ | ✅ | ✅ | ✅ نفس المسار | ✅ | ✅ | ⚠️ عام | ❓ |
| **WhatsApp Calling** | ✅ | ✅ (يتطلب `channel_voice`) | ✅ | ✅ حقل `calls` | ✅ | ✅ | ❌ | ❓ |
| **Facebook Messenger** | ✅ | ✅ OAuth + Pages | ✅ | ✅ عبر `facebook-messenger` gem | ✅ | ✅ | ⚠️ عام | ❓ |
| **Instagram (Direct)** | ✅ | ✅ OAuth مستقل + IG Login | ✅ | ✅ `/webhooks/instagram` + تحقق | ✅ | ✅ | ⚠️ عام | ❓ |
| **Telegram** | ✅ | ✅ Bot Token | ✅ | ✅ `/webhooks/telegram/:bot_token` | ✅ | ✅ | ⚠️ عام | ❓ |
| **Email (IMAP/SMTP/OAuth)** | ✅ | ✅ + Microsoft/Google OAuth | ✅ | ✅ ActionMailbox (SES/Mailgun/Mandrill/Postmark/Relay) | ✅ | ✅ | ⚠️ عام | ❓ |
| **Website Live Chat** | ✅ | ✅ | ✅ | ➖ (WebSocket مباشر) | ✅ | ✅ | ⚠️ عام | ❓ |
| **SMS — Twilio** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ عام | ❓ |
| **SMS — Bandwidth** | ✅ | ✅ | ✅ | ✅ `/webhooks/sms/:phone` | ✅ | ✅ | ⚠️ عام | ❓ |
| **LINE** | ✅ | ✅ | ✅ | ✅ `/webhooks/line/:channel_id` | ✅ | ✅ | ⚠️ عام | ❓ |
| **TikTok** | ✅ | ✅ | ⚠️ **مخفي** ما لم يُضبط `tiktokAppId` | ✅ HMAC-SHA256 | ✅ | ✅ | ⚠️ عام | ❓ |
| **API Channel (مخصّص)** | ✅ | ✅ + HMAC secret | ✅ | ✅ صادر | ✅ | ✅ | ⚠️ عام | ❓ |
| **Voice (SIP/Twilio)** | ✅ (EE) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❓ |
| **X / Twitter** | ⚠️ Model + Service + Vue موجودة | ⚠️ ENV موجودة | ❌ **غائب من `ChannelList.vue`** | ⚠️ `/webhooks/twitter` (CRC) | ⚠️ | ⚠️ | ❌ | ❌ **مُهلَك** |

### قراءة المصفوفة

**1. "موجود بالكود" لا يساوي "يعمل".** كل الأعمدة الخضراء أعلاه تعني أن Chatwoot 4.14.1 يوفّر تنفيذًا كاملًا ومختبَرًا. **لكن العمود الأخير (Production Ready) يبقى `❓` لكل قناة** لأن الجاهزية تعتمد كليًا على:
   - وجود `InstallationConfig` / متغيّرات بيئة صحيحة على `chat.lynomia.com`
   - موافقات Meta/TikTok على التطبيقات (App Review, Advanced Access)
   - عقود BSP/Twilio/Bandwidth فعّالة

   **لا شيء من ذلك قابل للتحقق من المستودع.** أي تصريح بأن قناة "تعمل" دون فحص الخادم سيكون تخمينًا.

**2. تطبيق الموبايل "عام" (⚠️) لكل القنوات:** يعرض المحادثات من أي قناة، لكن كما أُثبت في §10.4، **لا يميّزها بصريًا بسبب خطأ `channel_type`**، ولا يدعم أي إجراء خاص بقناة (قوالب WhatsApp مثلًا).

**3. Twitter/X مُهلَك فعليًا:** الكود موجود لكن أُزيل من واجهة إنشاء الـ Inbox في Upstream، وعَلَم الميزة `channel_twitter` أُعيد استخدامه لغرض آخر (`20260508000000_repurpose_channel_twitter_flag_...`). **لا يُنصح بإحيائه.**

**4. القناة الوحيدة التي مسّها Lynomia هي WhatsApp** — وبتغيير واحد فعّال فقط (اسم الـ Inbox).

### الخطوة التالية الإلزامية لإكمال هذه المصفوفة

لا يمكن ملء عمود `Production Ready` إلا بتشغيل تحقق على الخادم الحيّ:

```ruby
# للقراءة فقط — لا يُنفَّذ في Phase 0
Inbox.group(:channel_type).count
Channel::Whatsapp.pluck(:phone_number, :provider)
InstallationConfig.where(name: %w[FB_APP_ID IG_VERIFY_TOKEN WHATSAPP_APP_ID
                                  INSTAGRAM_APP_ID TIKTOK_APP_ID]).pluck(:name)
Message.where('created_at > ?', 30.days.ago).joins(:inbox).group('inboxes.channel_type').count
```

هذا يحوّل المصفوفة من **Supported** إلى **Configured / Working**.

---

## 14. WhatsApp Analysis — تحليل WhatsApp

### 14.1 نوع التكامل

**مزوّدان مدعومان** (`app/models/channel/whatsapp.rb:32`):
```ruby
PROVIDERS = %w[default whatsapp_cloud].freeze
```
- `whatsapp_cloud` → **Meta Cloud API مباشرة** (`Whatsapp::Providers::WhatsappCloudService`)
- `default` → **360dialog BSP** (`Whatsapp::Providers::Whatsapp360DialogService`)

### 14.2 Embedded Signup

**مدعوم بالكامل.** الخدمات المتحققة:
- `Whatsapp::EmbeddedSignupService` — التدفق الكامل
- `Whatsapp::TokenExchangeService` — تبديل الكود بـ token طويل الأمد
- `Whatsapp::PhoneInfoService` — جلب بيانات الرقم
- `Whatsapp::ChannelCreationService` — إنشاء القناة + الـ Inbox
- `Whatsapp::WebhookSetupService` / `WebhookTeardownService` — تسجيل/إلغاء الـ callback تلقائيًا
- الإعدادات: `WHATSAPP_APP_ID`, `WHATSAPP_CONFIGURATION_ID`, `WHATSAPP_APP_SECRET`, `WHATSAPP_API_VERSION`

### 14.3 مصفوفة القدرات

| القدرة | الحالة | الدليل |
|---|---|---|
| إنشاء Inbox يدوي | ✅ | `CloudWhatsapp.vue`, `360DialogWhatsapp.vue` |
| Embedded Signup | ✅ | `WhatsappEmbeddedSignup.vue` + `EmbeddedSignupService` |
| WABA / Business Account ID | ✅ | `provider_config['business_account_id']` |
| Phone Number ID | ✅ | `provider_config['phone_number_id']` |
| Access Token | ✅ مُشفَّر | `ApplicationRecord` external credentials encryption |
| إعداد Webhook تلقائي | ✅ | `after_commit :setup_webhooks, on: :create` (سطر 38) |
| `webhook_verify_token` تلقائي | ✅ `SecureRandom.hex(16)` | سطر 118-120 |
| التحقق من التوقيع | ✅ | `MetaTokenVerifyConcern` + `verify_meta_signature!` |
| مزامنة القوالب | ✅ + Pagination | `sync_templates`, `fetch_whatsapp_templates` |
| مُعالِجات القوالب | ✅ 4 خدمات | `TemplateProcessorService`, `PopulateTemplateParametersService`, `TemplateParameterConverterService`, `LiquidTemplateProcessorService` |
| قوالب الوسائط (header) | ✅ | `whatsapp_cloud_service.rb:154-176` |
| أزرار القوالب (URL/OTP) | ✅ | نفس المرجع |
| رسائل تفاعلية (Interactive) | ✅ | `send_interactive_text_message` (سطر 8) |
| أزرار / قوائم | ✅ عبر Interactive | |
| الوسائط (صور/فيديو/ملفات/صوت) | ✅ | `send_attachment_message` (سطر 117) |
| `media_url` | ⚠️ **مثبّت على `v13.0`** | `whatsapp_cloud_service.rb:79` — بينما بقية المسارات تستخدم `WHATSAPP_API_VERSION` |
| حالات التسليم/القراءة | ✅ | `incoming_message_whatsapp_cloud_service.rb` |
| نافذة الـ 24 ساعة | ✅ مُدارة عبر القوالب | |
| WhatsApp Flows | ❌ **غير مدعوم** | لا أثر لـ `flow` في الكود |
| WhatsApp Calling | ✅ (EE + `channel_voice`) | `enable_voice_calling!` / `disable_voice_calling!` |
| CSAT عبر قالب | ✅ | `Whatsapp::CsatTemplateService` |
| حملات (Campaigns) | ✅ | `Whatsapp::OneoffCampaignService` |
| أرقام متعددة | ✅ | كل `Channel::Whatsapp` = رقم واحد؛ عدة Inboxes ممكنة |
| شركات/حسابات متعددة | ⚠️ **مقيَّد** | القيد الفريد العالمي على `phone_number` (راجع §12.3) |
| منع تكرار الرسائل | ✅ | `Whatsapp::MessageDedupLock` |
| إعادة التفويض | ✅ | `Reauthorizable` + `Whatsapp::ReauthorizationService` + `HealthService` |
| أرقام معطّلة | ✅ | `INACTIVE_WHATSAPP_NUMBERS` |

### 14.4 تخصيصات Lynomia على WhatsApp

| # | التعديل | التقييم |
|---|---|---|
| 1 | `channel_creation_service.rb:69-71` — `build_inbox_name` يُرجع `@phone_info[:phone_number]` بدل `"{business_name} WhatsApp"` | ✅ **يعمل**. مقبول وظيفيًا. **لكن:** الحقل `Inbox#name` لا يفرض التفرد ⇒ لا كسر. الأثر: أسماء Inbox أقل قابلية للقراءة للوكلاء. قرار منتج، ليس عيبًا. |
| 2 | `app/models/channel/whatsapp.rb:142-143` — إضافة مسافة قبل `end` + تعليق `# تعطيل الانقطاع الإجباري للأبد وتثبيت الاتصال دائماً` | ❌ **التعليق كاذب**. لا يوجد أي تغيير في `Reauthorizable`، ولا في `prompt_reauthorization!`، ولا في `HealthService`. سلوك "الانقطاع الإجباري" **ما زال فعّالًا كما في Upstream**. أي مهندس يقرأ هذا التعليق سيبني على افتراض خاطئ. |

### 14.5 أمن بيانات الاعتماد

✅ **جيد.** `provider_config` مُشفَّر عبر آلية Chatwoot لتشفير بيانات الاعتماد الخارجية (`spec/models/application_record_external_credentials_encryption_spec.rb`)، ويعتمد على `ACTIVE_RECORD_ENCRYPTION_*`.

⚠️ **تحذير تشغيلي:** إذا لم تُضبط مفاتيح `ACTIVE_RECORD_ENCRYPTION` على الخادم، فالتشفير لا يعمل. **يتطلب تحقق تشغيلي.**

---

## 15. Facebook Analysis — تحليل Facebook

| المرحلة | الحالة | الدليل |
|---|---|---|
| OAuth | ✅ | `config/routes.rb:106-108` → `register_facebook_page`, `facebook_pages` |
| Meta App | ✅ عبر `FB_APP_ID` / `FB_APP_SECRET` | `installation_config.yml:123-133` |
| الصفحات (Pages) | ✅ اختيار متعدد | `Facebook.vue` |
| الصلاحيات / Scopes | ✅ | مُدارة عبر `koala` + `facebook-messenger` |
| دورة حياة الـ Token | ✅ Page tokens + `Reauthorizable` | `app/models/channel/facebook_page.rb` |
| اشتراك Webhook | ✅ | `config/initializers/facebook_messenger.rb` |
| رسائل واردة | ✅ | `facebook-messenger` gem → Jobs |
| رسائل صادرة | ✅ | `app/services/facebook/send_on_facebook_service.rb` |
| المرفقات | ✅ | نفس الخدمة |
| حالة الرسالة | ✅ | echo/delivery events |
| إعادة ربط الحساب | ✅ | `Reauthorizable` |
| الأخطاء | ✅ | `prompt_reauthorization!` |
| انتهاء الـ Token | ✅ يُكتشف ويُبلّغ | |

**التحقق من التوقيع:** ✅ عبر `MetaTokenVerifyConcern` (مُستخدَم في WhatsApp؛ وFacebook Messenger gem يتحقق داخليًا عبر `FB_APP_SECRET`).

**الحكم:** كود موروث كامل وناضج. **لا يوجد أي تعديل من Lynomia.** جاهزيته تعتمد 100% على تهيئة Meta App وموافقات `pages_messaging`.

---

## 16. Instagram Analysis — تحليل Instagram

Chatwoot 4.14.1 يوفّر **مسارَي تكامل** لـ Instagram:

| المسار | الوصف | الحالة |
|---|---|---|
| **(أ) عبر Facebook Page** | `Channel::FacebookPage` مع IG مرتبط | ✅ موروث |
| **(ب) Instagram Login مستقل** | `Channel::Instagram` — `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, `INSTAGRAM_VERIFY_TOKEN` | ✅ موروث |

| المرحلة | الحالة | الدليل |
|---|---|---|
| OAuth مستقل | ✅ | `config/routes.rb:649` → `instagram/callback` |
| حسابات Professional | ✅ مطلوبة | `app/models/channel/instagram.rb` |
| `instagram_id` فريد | ✅ | سطر 28 |
| Subscribe / Unsubscribe | ✅ | `subscribe` (45)، `unsubscribe` (59) |
| Webhook + تحقق | ✅ | `/webhooks/instagram` (GET verify + POST events) |
| رسائل واردة | ✅ | `Instagram::WebhooksBaseService`, `Instagram::Messenger::*` |
| رسائل صادرة | ✅ | `Instagram::SendOnInstagramService`, `BaseSendService` |
| المرفقات | ✅ | |
| حالة القراءة | ✅ | `Instagram::ReadStatusService` |
| تجديد الـ Token | ✅ | `Instagram::RefreshOauthTokenService` |
| Human Agent tag | ✅ | `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` |
| إصدار API قابل للضبط | ✅ | `INSTAGRAM_API_VERSION` |

**الحكم:** التكامل الأكثر نضجًا بعد WhatsApp. **لا تعديلات من Lynomia.**

---

## 17. Other Channels — القنوات الأخرى

| القناة | الملاحظات |
|---|---|
| **Telegram** | Bot Token فقط، webhook لكل بوت (`/webhooks/telegram/:bot_token`). ⚠️ **الـ token في مسار الـ URL** — سيظهر في سجلات الوصول (Nginx access log). سلوك Upstream، لكنه مخاطرة أمنية معروفة. |
| **LINE** | `line-bot-api`، webhook `/webhooks/line/:line_channel_id`. كامل. |
| **Email** | الأغنى إعدادًا: IMAP/SMTP + Microsoft OAuth + Google OAuth + ActionMailbox (SES/SNS، Mailgun، Mandrill، Postmark، Relay). `MAILER_INBOUND_EMAIL_DOMAIN`. مؤخرًا: `20260507000000_add_imap_authentication_to_channel_email`. |
| **Website Live Chat** | ودجت كامل (`app/javascript/widget/`) + `WIDGET_TOKEN_EXPIRY` + HMAC identity validation. |
| **SMS** | مزوّدان: Twilio و Bandwidth، لكل منهما شاشة إعداد. |
| **API Channel** | قناة عامة مع `secret` (أُضيف في `20260324070828_add_secret_to_channel_api`) لتوقيع الـ webhooks الصادرة. + `email_continuity_on_api_channel`. |
| **TikTok** | كامل مع HMAC-SHA256، لكنه **مخفي من الواجهة** إن لم يُضبط `tiktokAppId` (`ChannelList.vue:19-21, 82-89`). |
| **Voice** | ميزة Enterprise (`enterprise/lib/voice/`) — SIP/Twilio Voice + `Channel::Voice`. |
| **Twitter/X** | **مُهلَك.** موجود بالكود، غائب من الواجهة، عَلَم الميزة أُعيد استخدامه. **لا تستثمر فيه.** |

---

## 18. Realtime Messaging — الرسائل الفورية

### 18.1 الخادم

| المكوّن | التفصيل |
|---|---|
| البروتوكول | ActionCable على Redis adapter (`config/cable.yml`) |
| القناة | `RoomChannel` — `app/channels/room_channel.rb` |
| المصادقة | `pubsub_token` (للعميل) أو `pubsub_token` + `user_id` + `account_id` (للوكيل) |
| التوزيع | `app/dispatchers/` → `ActionCableListener` |
| Presence | `Redis::Alfred` مع مفاتيح TTL |
| التوسّع | ✅ Redis pub/sub ⇒ عدة عمليات Puma تعمل |

### 18.2 الموبايل

| البند | الحالة |
|---|---|
| المكتبة | `web_socket_channel` — **تنفيذ ActionCable يدوي** |
| معالجة البروتوكول | ✅ `welcome`, `ping`, `confirm_subscription`, `reject_subscription` (أسطر 899-920) |
| الاشتراك | `{channel: 'RoomChannel', pubsub_token, account_id, user_id}` |
| إعادة الاتصال | ⚠️ تأخير ثابت 5 ثوانٍ، **بلا exponential backoff، بلا حد أقصى** (أسطر 664-671) |
| Presence / heartbeat | ⚠️ `_presenceTimer` مُعرَّف لكن الاستخدام محدود |
| Typing indicator | ✅ يُرسل `typing_status` |
| **المشكلة الأساسية** | التطبيق يفتح **اتصالًا واحدًا** ويُعيد الاشتراك عند تغيير المحادثة (`subscribeToConversation`) — لكن **لا يُلغي الاشتراك القديم**. مع تصفّح عدة محادثات تتراكم الاشتراكات على نفس السوكيت. |
| عند فقد الاتصال | لا يوجد **إعادة مزامنة (re-sync)** للرسائل الفائتة ⇒ **فقدان رسائل صامت** بعد انقطاع الشبكة | **P1** |

---

## 19. Notifications — الإشعارات

### 19.1 الخادم

| المكوّن | الحالة |
|---|---|
| نموذج | `Notification` + `NotificationSubscription` (fcm / webpush) |
| FCM | ✅ **HTTP v1** مع Service Account + تخزين مؤقت للـ token (`app/services/notification/fcm_service.rb`) |
| الإعداد | `FIREBASE_PROJECT_ID` + `FIREBASE_CREDENTIALS` (JSON كامل في `InstallationConfig`) |
| Web Push | ✅ VAPID |
| البريد | ✅ `Notification::EmailNotificationService` |
| المهام | `push_notification_job`, `email_notification_job`, `remove_duplicate_notification_job`, `remove_old_notification_job`, `reopen_snoozed_notifications_job` |
| Push Relay | ✅ اختياري `ENABLE_PUSH_RELAY_SERVER` (لتطبيقات Chatwoot الرسمية) |
| تشخيص | ✅ `SuperAdmin::PushDiagnosticsController` |

### 19.2 الموبايل

| البند | الحالة |
|---|---|
| التسجيل | ✅ `POST /api/v1/notification_subscriptions` بعد تسجيل الدخول |
| نوع الاشتراك | `fcm` مع `push_token`, `device_id`, `devicePlatform` |
| العرض | ✅ `flutter_local_notifications` |
| مشروع Firebase | `lynomia-chat-fc5e0` / `com.Lynomia.Lynomia_chat` |
| ⚠️ **حرج** | `ENABLE_PUSH_RELAY_SERVER` من Chatwoot يوجّه الإشعارات لتطبيقات **Chatwoot الرسمية**. لتطبيق Lynomia يجب أن يكون **معطّلًا** وأن تُضبط `FIREBASE_CREDENTIALS` بحساب خدمة مشروع `lynomia-chat-fc5e0`. **يتطلب تحقق تشغيلي — إن كان مفعّلًا فالإشعارات لن تصل أبدًا.** |
| ⚠️ | لا يُلغى تسجيل الـ FCM token عند تسجيل الخروج ⇒ إشعارات تصل لجهاز مستخدم سابق | **P1 — أمني** |
| ❌ | لا معالجة لنقر الإشعار (deep-link إلى المحادثة) | P2 |

---

## 20. SaaS & Billing — الطبقة التجارية

### 20.1 الحالة الفعلية

| البند | داخل Chatwoot | في `lynomia.com` | الحكم |
|---|---|---|---|
| التسجيل (Registration) | ✅ موجود (`ENABLE_ACCOUNT_SIGNUP`) | ✅ `/api/register/google` | **مُكرَّر ومتضارب** |
| المؤسسات / الحسابات | ✅ `Account` | ❓ | يوجد نموذج `Company` في EE |
| الاشتراكات | ✅ Stripe (EE) — 8 خدمات | ✅ (المسار الفعلي) | **Chatwoot مُعطَّل عمليًا** |
| الخطط | ✅ `CHATWOOT_CLOUD_PLANS` | ✅ `/api/plans/chat` | غير مُهيّأ في Chatwoot |
| الفترات التجريبية | ❌ | ❓ | |
| الحدود (Limits) | ✅ آلية موجودة (EE) | ❓ | **غير مُهيّأة ⇒ بلا حدود** |
| حد الوكلاء | ✅ `agent_limits` | ❓ | غير مُفعّل |
| حد الـ Inboxes | ✅ `get_limits(:inboxes)` | ❓ | غير مُفعّل |
| حد القنوات | ❌ غير موجود أصلًا | ❓ | |
| حد أرقام WhatsApp | ❌ غير موجود | ❓ | |
| التخزين | ❌ لا حد | ❓ | |
| الفوترة / الفواتير | ✅ Stripe Portal | ✅ | **مُوجَّه للخارج** |
| Stripe | ✅ `webhooks/stripe`, `HandleStripeEventService`, `TopupCheckoutService` | ✅ `flutter_stripe` في الموبايل | **مساران متوازيان** |
| ترقية/تخفيض | ✅ عبر Stripe | ❓ | |
| سجل الدفعات | ➖ | ✅ `/api/my/payment/chat` | موبايل فقط |
| Google Play Billing | ❌ | ✅ `/api/verify-google-play-purchase` | موبايل فقط |
| Feature Gating | ✅ `Account#feature_enabled?` + `subscribed_features` | ❓ | **غير مربوط بـ lynomia.com** |
| عزل المستأجرين | ✅ قوي على مستوى DB/Controller | — | ✅ |

### 20.2 الفجوة الحرجة

```
lynomia.com يعرف من دفع.
Chatwoot لا يعرف.
لا يوجد أي جسر بينهما في الكود.
```

**النتيجة العملية:** حساب لم يدفع، أو انتهى اشتراكه، **يستمر في العمل بكامل الميزات وبلا حدود داخل Chatwoot**، لأن:
1. `usage_limits` في OSS = 100,000 لكل شيء
2. `CHATWOOT_CLOUD_PLANS` غير مُهيّأ (لا دليل عليه)
3. `subscribed_features` تُرجع `[]` عندما `CHATWOOT_CLOUD_PLAN_FEATURES` فارغ
4. لا يوجد أي webhook من `lynomia.com` إلى Chatwoot لتحديث الخطة

**هذا هو أخطر عائق تجاري (P0) في المشروع.**

---

## 21. Users / Teams / Permissions — المستخدمون والصلاحيات

### 21.1 مستويات الإدارة

| المستوى | التنفيذ | نطاق الوصول |
|---|---|---|
| **Lynomia Super Admin** | `SuperAdmin::*` (Administrate) على `/super_admin` | **كل شيء**: الحسابات، المستخدمين، `InstallationConfig`، AppConfigs، Access Tokens، Platform Apps، Banners، Push Diagnostics، Seed |
| **Account Administrator** | `AccountUser.role = administrator` (1) | كامل الحساب: الإعدادات، الـ Inboxes، الوكلاء، الفرق، الفوترة، التقارير، التكاملات |
| **Custom Roles (EE)** | `enterprise/app/models/custom_role.rb` + `AccountUser#custom_role_id` | صلاحيات دقيقة قابلة للتكوين |
| **Agent** | `AccountUser.role = agent` (0) | المحادثات في الـ Inboxes المُسندة فقط |
| **Team** | `Team` + `TeamMember` | تجميع منطقي، ليس مستوى صلاحية |
| **Agent Bot** | `AgentBot` + `secret` | وصول برمجي محدود |
| **Platform App** | `PlatformApp` + `PlatformAppPermissible` | Platform API (إنشاء حسابات/مستخدمين) |

**ملاحظة:** لا يوجد دور "Supervisor" أصيل — يُحاكى عبر **Custom Roles** في EE.

### 21.2 عزل المستأجرين (Tenant Isolation)

| البند | التقييم |
|---|---|
| على مستوى DB | ✅ `account_id` على كل جدول رئيسي |
| على مستوى Controller | ✅ `Current.account` من `params[:account_id]` + `Pundit` |
| على مستوى Policy | ✅ `app/policies/**` + `enterprise/app/policies/**` |
| **الثغرة الفعلية** | ⚠️ **قيد `phone_number` الفريد العالمي** على `channel_whatsapp` — يُسرّب وجود رقم لدى مستأجر آخر عبر رسالة الخطأ (`errors.whatsapp.phone_number_already_exists`) |
| **الثغرة من جهة العميل** | ❌ الموبايل يستخدم `accountId ?? 4` كاحتياطي — إن فشل قراءة الحساب، يحاول الوصول للحساب 4 |
| **الثغرة التاريخية** | كود مُعلَّق في الموبايل يشير إلى `/api/v1/accounts/1/...` (سطر 202) — دليل على تجارب سابقة بحسابات مضمّنة |

---

## 22. Security Findings — النتائج الأمنية

> **لا يحتوي هذا القسم على أي سرّ فعلي. تُذكر المواقع وأنواع المخاطر فقط.**

### 22.1 أسرار في Git

| المستودع | النتيجة |
|---|---|
| `lynomiachat` | ✅ **نظيف.** لا `.env` مُتتبَّع (فقط `.env.example` بقيم وهمية). لا مفاتيح خاصة. الملف الوحيد `config/rds-ca-2019-root.pem` هو **شهادة عامة** من AWS (ليست سرًا). |
| `lynomia-chat-app98` | ⚠️ **ملاحظتان:** (1) `android/app/google-services.json` مُتتبَّع — هذا **مقبول** (مفاتيح Firebase للعميل عامة بطبيعتها) لكنه يكشف معرّف المشروع وحزمة التطبيق. (2) `local.properties` **مُتتبَّع بالخطأ** — يكشف مسار نظام ملفات المطوّر (`C:\Users\<اسم>\...`) ⇒ تسريب معلومات طفيف + يخالف تعليمات الملف نفسه ("must *NOT* be checked into Version Control"). ✅ لا ملفات `.jks` / `key.properties` مُتتبَّعة. |

### 22.2 قائمة النتائج

| # | النتيجة | الموقع | الخطورة |
|---|---|---|---|
| S-1 | **رمز الوصول يُطبع في سجلّات الجهاز** — `print('✅ Access token saved: $_authToken')` | `lynomia-chat-app98/lib/shared/network/chatwoot_api_service.dart:1025, 1139, 1927` | **P0** |
| S-2 | **كلمة المرور تُرسل إلى نظامين** — نفس بيانات الاعتماد تُعاد إرسالها إلى `lynomia.com/api/login` | نفس الملف: 1045-1090 | **P0** |
| S-3 | **الرموز في تخزين غير مشفّر** — `SharedPreferences` بدل `flutter_secure_storage` | `lib/shared/network/local/cache_helper.dart` | **P1** |
| S-4 | **`validateStatus: (status) => true`** — يُعطّل كل فحص أخطاء HTTP في العميل | نفس الملف: 399 | **P1** |
| S-5 | **رقم حساب احتياطي مضمّن (`?? 4`)** — مخاطرة عزل مستأجرين | نفس الملف: 686, 709, 730, 1173 | **P1** |
| S-6 | **لا إلغاء لتسجيل FCM عند الخروج** — إشعارات لمستخدم سابق على الجهاز | `clearAuth()` سطر 1483 | **P1** |
| S-7 | **Sign in with Apple يشير إلى نطاق وهمي** — `https://your-backend.com/...` | `lib/layout/cubit/cubit.dart:1408` | **P1** |
| S-8 | **`local.properties` مُتتبَّع** | `lynomia-chat-app98/local.properties` | P3 |
| S-9 | **تسجيل مُكرَّر لـ OmniAuth** — `google_oauth2` مُسجَّل مرتين (Devise + OmniAuth::Builder) بخيارات مختلفة (`prompt: select_account` مقابل `provider_ignores_state: true`) ⇒ سلوك غير محدّد في تدفق OAuth | `config/initializers/devise.rb:251` مقابل `config/initializers/omniauth.rb:5` | **P1** |
| S-10 | **`provider_ignores_state: true`** في `omniauth.rb` — يُعطّل حماية CSRF في تدفق OAuth (سلوك Upstream) | `config/initializers/omniauth.rb:7` | P2 |
| S-11 | **Telegram bot token في مسار الـ URL** — يظهر في سجلات Nginx | `config/routes.rb:614` | P2 |
| S-12 | **`media_url` مثبّت على Graph API v13.0** — إصدار قديم جدًا، قد يُسحب من الخدمة | `app/services/whatsapp/providers/whatsapp_cloud_service.rb:79` | P2 |
| S-13 | **قناة WhatsApp: قيد فريد عالمي** يُسرّب وجود رقم عبر الحسابات | `db/schema.rb` — `index_channel_whatsapp_on_phone_number` | P1 |
| S-14 | **`root@server2.lynomia.com` كمؤلف الـ commit** — التطوير على خادم الإنتاج مباشرة | `git log 7bb7e5d8` | **P1 — عملياتي** |

### 22.3 الضوابط الأمنية الموجودة والسليمة ✅

| الضابط | الحالة |
|---|---|
| تخزين كلمة المرور | ✅ Devise / bcrypt + `secure_password.rb` |
| MFA | ✅ موجود (`run_mfa_spec.yml`, `MfaVerification`) |
| CSRF | ✅ Rails + `omniauth-rails_csrf_protection` |
| CORS | ✅ `config/initializers/cors.rb` |
| CSP | ✅ `config/initializers/content_security_policy.rb` |
| Permissions-Policy | ✅ |
| Rate limiting | ✅ `rack-attack` — login/reset/confirmation/MFA/super_admin/req-per-ip |
| Authorization | ✅ Pundit شامل |
| IDOR | ✅ مُخفَّف عبر `Current.account` scoping |
| تحقق توقيع Webhooks | ✅ Meta / TikTok / Shopify / Stripe |
| Webhook secrets | ✅ (migrations 2026-02/03) |
| رفع الملفات | ✅ `MAXIMUM_FILE_UPLOAD_SIZE` + ActiveStorage + `DIRECT_UPLOADS_ENABLED` |
| تصفية السجلات | ✅ `filter_parameter_logging.rb` |
| تشفير بيانات الاعتماد الخارجية | ✅ ActiveRecord Encryption |
| فحص أسرار CI | ✅ متاح عبر GitHub secret scanning |

---

## 23. Performance & Scalability — الأداء وقابلية التوسّع

| البند | التقييم |
|---|---|
| Web tier | ✅ Puma بلا حالة ⇒ توسّع أفقي |
| Workers | ✅ Sidekiq بصفوف متعدّدة الأولوية |
| Realtime | ✅ ActionCable + Redis adapter ⇒ يتوسّع |
| DB | ⚠️ نقطة اختناق وحيدة — لا read replicas مُعدّة افتراضيًا |
| نمو `messages` | ⚠️ **بلا حدود** — لا partitioning ولا أرشفة |
| البحث | ⚠️ Postgres افتراضيًا؛ Elasticsearch اختياري (`searchkick`) |
| التقارير | ⚠️ استعلامات ثقيلة؛ `report_rollup` موجود لكن **معطّل افتراضيًا** (`features.yml:77-79`) |
| CDN | ✅ مدعوم عبر `ASSET_CDN_HOST` |
| ملفات ثقيلة | ✅ S3/Azure/GCS + Direct Uploads |
| **الموبايل — لا Pagination** | ❌ **P1** — `fetchConversations` و `fetchMessagesAdminApi` تجلبان كل شيء. حساب بـ 5,000 محادثة سيُعطّل التطبيق ويُثقل الخادم |
| **الموبايل — لا Caching** | ❌ إعادة جلب كاملة عند كل فتح شاشة |
| **الموبايل — لا Retry/Backoff** | ❌ إعادة اتصال WS كل 5 ثوانٍ بلا حد ⇒ عاصفة اتصالات (thundering herd) عند انقطاع الخادم |

---

## 24. DevOps / Deployment — النشر والبنية التحتية

### 24.1 المتاح في المستودع

| البند | الحالة |
|---|---|
| Docker | ✅ `docker/Dockerfile` + `docker-compose.yaml` / `.production.yaml` / `.test.yaml` |
| systemd | ✅ `deployment/chatwoot-web.1.service`, `chatwoot-worker.1.service`, `.target` |
| Nginx | ✅ `deployment/nginx_chatwoot.conf` |
| سكربتات التثبيت | ✅ `setup_18.04.sh`, `setup_20.04.sh` (Ubuntu — قديمة) |
| Capistrano | ✅ `Capfile` |
| CleverCloud | ✅ `clevercloud/` |
| Heroku | ✅ `app.json` |
| Procfiles | ✅ `Procfile`, `.dev`, `.test`, `.tunnel` |
| CI (GitHub Actions) | ✅ **16 workflow** موروثة: `run_foss_spec`, `run_mfa_spec`, `frontend-fe`, `lint_pr`, `size-limit`, `deploy_check`, `test_docker_build`, `publish_foss_docker`, `publish_ee_docker`, `nightly_installer`, ... |

### 24.2 الفجوات الحرجة

| # | الفجوة | الخطورة |
|---|---|---|
| D-1 | **لا يوجد أي CI/CD خاص بـ Lynomia.** كل الـ workflows موروثة وتستهدف مستودع Chatwoot (أسماء صور Docker، أسرار، بيئات). **لا خط نشر آلي لـ `chat.lynomia.com`.** | **P0** |
| D-2 | **التطوير يتم على خادم الإنتاج** — مؤلف الـ commit هو `root@server2.lynomia.com`. لا بيئة staging، لا مراجعة، لا اختبار قبل النشر. | **P0** |
| D-3 | **لا CI لتطبيق الموبايل إطلاقًا** — لا بناء آلي، لا توقيع آلي، لا رفع إلى المتاجر. | **P1** |
| D-4 | **لا وثائق نشر خاصة بـ Lynomia** — لا يوجد ملف يشرح كيف يُنشر النظام، ما هي متغيّرات البيئة المطلوبة، أو كيف يرتبط بـ `lynomia.com`. | **P1** |
| D-5 | **لا مراقبة (Monitoring) مُثبَّتة** — APM متاح (New Relic/Datadog/Sentry/Elastic) لكن لا دليل على تفعيل أي منها. | **P1** |
| D-6 | **لا استراتيجية نسخ احتياطي موثّقة** | **P1** |
| D-7 | **`lynomia.com` خارج نطاق أي تدقيق** — نظام إنتاجي حرج بلا مستودع معروف | **P0** |

---

## 25. Testing & Quality — الاختبارات والجودة

| البند | `lynomiachat` | `lynomia-chat-app98` |
|---|---|---|
| اختبارات الوحدة/التكامل | ✅ **733 spec** (RSpec) | ❌ **0** |
| اختبارات الواجهة | ✅ **349 spec** (Vitest) | ❌ **0** |
| E2E | ✅ Playwright (`tests/playwright/`) | ❌ |
| Lint (Ruby) | ✅ RuboCop + `rubocop/` مخصّص | ➖ |
| Lint (JS) | ✅ ESLint (Airbnb + Vue3) | — |
| Lint (Dart) | ⚠️ `analysis_options.yaml` موجود، **لا دليل على تشغيله** | |
| **اختبارات لتخصيصات Lynomia** | ❌ **صفر** — لا spec لأي من الملفات السبعة | |
| **كسر Lint مُدخَل** | ❌ `billing.routes.js:2` — `INSTALLATION_TYPES` مُستورد وغير مستخدم ⇒ **ESLint `no-unused-vars` يفشل** | |
| **مخالفات `CLAUDE.md`** | ❌ `Navbar.vue` و `login/Index.vue` يستخدمان CSS مخصّصًا بدل Tailwind (مخالفة صريحة لـ "Tailwind Only") | |

**الحكم:** جودة Upstream ممتازة. **جودة طبقة Lynomia معدومة** — لا اختبار، لا lint، لا مراجعة.

---

## 26. UX/UI Issues — مشاكل تجربة المستخدم

| # | المشكلة | الموقع | الخطورة |
|---|---|---|---|
| U-1 | **تسريب CSS عالمي** — `<style>` **غير مُنطاق** في `login/Index.vue` يعرّف `#app { background: linear-gradient(...) }` و `.leading-6, input { color: white !important }`. بما أن الـ SFC يُحمَّل ضمن نفس الحزمة، هذه القواعد تُطبَّق **على كامل التطبيق**، ويمكن أن تجعل نصوص الحقول بيضاء على خلفية بيضاء في شاشات أخرى | `app/javascript/v3/views/login/Index.vue:358-377` | **P1** |
| U-2 | **كسر i18n** — `Login to lynomia chat` مضمّن نصًا بدل `$t('LOGIN.TITLE')`، مما يُلغي دعم العربية وكل اللغات في صفحة الدخول | نفس الملف: 253-254 | **P1** |
| U-3 | **إلغاء White-labeling** — حُذف `globalConfig.logo` واستُبدل برابط ثابت `https://lynomia.com/img/logo.png` ⇒ فشل تحميل الشعار إن كان `lynomia.com` بطيئًا/محجوبًا، ويُلغي إعداد الشعار من Super Admin. يخالف صراحةً إرشاد `CLAUDE.md` باستخدام `replaceInstallationName` | نفس الملف: 246-252 | **P1** |
| U-4 | **`class="bg-whit"`** — خطأ إملائي في اسم صنف Tailwind (`bg-white` → `bg-whit`)، عُوِّض بقاعدة CSS مخصّصة | نفس الملف: 276 | P2 |
| U-5 | **Navbar تسويقي داخل تطبيق** — شريط بروابط "Home / Terms / Privacy / Contact / About Us" وزر "Get Started" يشير إلى `#pricing` **غير موجود في الصفحة** | `Navbar.vue:56` | P2 |
| U-6 | **روابط Navbar متضاربة** — نسخة سطح المكتب تشير إلى `https://lynomia.com/terms`، ونسخة الجوال إلى `/terms` (مسار نسبي على `chat.lynomia.com` ⇒ **404**) | `Navbar.vue:45-49` مقابل `75-79` | P2 |
| U-7 | **صفحة الفوترة تعرض "Redirecting..." غير مترجم** ثم تخرج من التطبيق | `billing/Index.vue:14` | P2 |
| U-8 | **الموبايل: كل الـ Inboxes بأيقونة واحدة** (راجع §10.4) | `inbox_selection_screen.dart:279` | P2 |
| U-9 | **الموبايل: رسائل خطأ عربية ثابتة** غير مارّة بنظام `AppLocalizations` رغم وجوده | `chatwoot_api_service.dart` — عدة مواضع | P2 |
| U-10 | **الموبايل: `pubspec.yaml` description = "A new Flutter project."** و README قالب افتراضي | | P3 |

---

## 27. Technical Debt — الدين التقني

### 27.1 في `lynomia-chat-app98` (الأثقل)

| البند | الحجم |
|---|---|
| **كود ميت مُعلَّق** | `chatwoot_api_service.dart` — الأسطر **1–345 مُعلَّقة بالكامل** (~16% من الملف) |
| **`dio_helper.dart` مُكرَّر** | نسخة مُعلَّقة كاملة + نسخة حية متطابقة تقريبًا؛ **والملف نفسه غير مستخدم** (كل الطلبات تمر عبر `ChatwootApiService._dio`) |
| **API مزدوج** | مسارات Public/Widget ومسارات Agent متعايشة؛ 5 دوال ميتة |
| **`chatwoot_client_sdk`** | تبعية SDK العميل في تطبيق وكيل، **بلا قيد إصدار** |
| **`dio ^4.0.6`** | إصدار رئيسي متأخر |
| **ملف بـ 2125 سطر** | `ChatwootApiService` — God Object يجمع الشبكة والحالة والتخزين والـ WebSocket |
| **صفر اختبارات** | |
| **مخالفة `CLAUDE.md`** | "Don't write multiple versions or backups for the same logic" — مُخالَفة في كل ملف تقريبًا |

### 27.2 في `lynomiachat`

| البند | الحجم |
|---|---|
| **CSS مخصّص** | 2 ملف يخالفان قاعدة "Tailwind Only" |
| **Import غير مستخدم** | يكسر ESLint |
| **تعليق كاذب** | `# تعطيل الانقطاع الإجباري...` بلا تنفيذ |
| **تسجيل OAuth مُكرَّر** | |
| **صفحة فوترة مُفرَّغة** | تعارض merge مؤكّد مع Upstream |
| **Twitter مُهلَك** | كود ميت موروث (قرار Upstream، ليس ذنب Lynomia) |

---

## 28. Bugs / Broken Features — الأخطاء والميزات المكسورة

> بصيغة: **المستودع | الملف | السلوك الحالي | السلوك المتوقع | الخطورة | التبعية | الاتجاه المقترح**

### B-1 — التعليق الكاذب على قناة WhatsApp
- **المستودع:** `lynomiachat`
- **الملف:** `app/models/channel/whatsapp.rb:142-143`
- **السلوك الحالي:** الـ commit أضاف تعليقًا `# تعطيل الانقطاع الإجباري للأبد وتثبيت الاتصال دائماً` ومسافة بادئة على `end`. **صفر تغيير منطقي.** آلية `Reauthorizable` / `prompt_reauthorization!` / `HealthService` تعمل تمامًا كما في Upstream، وستستمر في تعطيل القناة عند فشل الاتصال بـ Meta.
- **السلوك المتوقع:** إما تنفيذ السلوك المُعلن، أو حذف التعليق.
- **الخطورة:** **P1** (وهم وظيفي يقود لقرارات خاطئة)
- **التبعية:** لا شيء
- **الاتجاه:** حذف التعليق والمسافة (يزيل تعارض merge مجانًا). إن كان "عدم قطع الاتصال" مطلوبًا فعليًا، يُنفَّذ كـ `enterprise/` أو `custom/` override لـ `Reauthorizable` مع سياسة إعادة محاولة، لا كتعطيل أعمى.

### B-2 — Import غير مستخدم يكسر Lint
- **المستودع:** `lynomiachat`
- **الملف:** `app/javascript/dashboard/routes/dashboard/settings/billing/billing.routes.js:2`
- **السلوك الحالي:** `import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';` بينما كل استخداماته حُذفت ⇒ `pnpm eslint` يفشل.
- **السلوك المتوقع:** بناء نظيف.
- **الخطورة:** P2 (P1 إذا رُبط CI ببوابة lint)
- **التبعية:** لا شيء
- **الاتجاه:** حذف السطر.

### B-3 — تسريب CSS عالمي من صفحة الدخول
- **المستودع:** `lynomiachat`
- **الملف:** `app/javascript/v3/views/login/Index.vue:358-377`
- **السلوك الحالي:** `<style>` بلا `scoped` يعرّف `#app`, `.new, label`, `.leading-6, input { color: white !important }`. يؤثر على كل شاشة تُحمَّل بعد صفحة الدخول في نفس الجلسة.
- **السلوك المتوقع:** تنسيق محصور بصفحة الدخول.
- **الخطورة:** **P1**
- **التبعية:** يجب حلّه قبل أي إعادة تصميم للـ Dashboard
- **الاتجاه:** نقل الـ branding إلى Chatwoot Custom Branding + متغيّرات Tailwind، لا `<style>` عالمي.

### B-4 — كسر i18n وWhite-labeling في صفحة الدخول
- **المستودع:** `lynomiachat`
- **الملف:** `app/javascript/v3/views/login/Index.vue:246-254`
- **السلوك الحالي:** عنوان إنجليزي ثابت + شعار من `https://lynomia.com/img/logo.png`؛ حُذف `globalConfig.logo` و `replaceInstallationName($t('LOGIN.TITLE'))`.
- **السلوك المتوقع:** عنوان مترجم + شعار من `InstallationConfig`.
- **الخطورة:** **P1** — يمنع إطلاق عربي/عالمي
- **التبعية:** §26 U-1..U-3
- **الاتجاه:** استخدام `LOGO`, `LOGO_DARK`, `INSTALLATION_NAME` من Super Admin + `replaceInstallationName` (كما ينص `CLAUDE.md`).

### B-5 — روابط Navbar للجوال مكسورة
- **المستودع:** `lynomiachat`
- **الملف:** `app/javascript/dashboard/components/Navbar.vue:75-79`
- **السلوك الحالي:** روابط نسبية `/terms`, `/privacy`, `/about_us` تُحلّ على `chat.lynomia.com` ⇒ **404**. النسخة المكتبية تستخدم روابط مطلقة صحيحة.
- **السلوك المتوقع:** توافق بين النسختين.
- **الخطورة:** P2
- **التبعية:** لا شيء
- **الاتجاه:** توحيد الروابط المطلقة.

### B-6 — أيقونات القنوات لا تُطابق أبدًا في الموبايل
- **المستودع:** `lynomia-chat-app98`
- **الملف:** `lib/modules/inbox_selection/inbox_selection_screen.dart:279-345`
- **السلوك الحالي:** `switch (channelType?.toLowerCase())` يقارن بـ `'whatsapp'` بينما الخادم يُرجع `"Channel::Whatsapp"` (`app/views/api/v1/models/_inbox.json.jbuilder:5`). لا حالة تُطابق ⇒ أيقونة `Icons.inbox` رمادية واسم خام `"Channel::Whatsapp"` لكل قناة.
- **السلوك المتوقع:** أيقونة ولون واسم لكل قناة.
- **الخطورة:** P2 (ولكنه يُبطل ادعاء "Omnichannel" في الموبايل بصريًا)
- **التبعية:** عقد الـ API
- **الاتجاه:** تطبيع القيمة (`channelType.split('::').last.toLowerCase()`) أو إضافة حقل `channel` مبسّط في الـ API.

### B-7 — Sign in with Apple يشير إلى نطاق وهمي
- **المستودع:** `lynomia-chat-app98`
- **الملف:** `lib/layout/cubit/cubit.dart:1408`
- **السلوك الحالي:** `redirectUri: 'https://your-backend.com/callbacks/sign_in_with_apple'` مع تعليق `// ← من زميلك`.
- **السلوك المتوقع:** نطاق Lynomia الحقيقي.
- **الخطورة:** **P1** — **مانع لقبول App Store** إن كان Google Sign-In مفعّلًا (سياسة Apple تُلزم بـ Sign in with Apple)
- **التبعية:** يحتاج endpoint على `lynomia.com`
- **الاتجاه:** تحديد الـ callback الحقيقي، أو إزالة Apple Sign-In بالكامل إن لم يُدعم.

### B-8 — لا Pagination في الموبايل
- **المستودع:** `lynomia-chat-app98`
- **الملف:** `chatwoot_api_service.dart:1298` (`fetchConversations`), `:1350` (`fetchMessagesAdminApi`)
- **السلوك الحالي:** لا `page` ولا `before`. جلب كامل في كل مرة.
- **السلوك المتوقع:** ترقيم صفحات + تحميل تدريجي.
- **الخطورة:** **P1** عند أي حجم إنتاجي
- **التبعية:** لا شيء (الـ API يدعمه أصلًا)
- **الاتجاه:** إضافة `page` للمحادثات و `before` للرسائل.

### B-9 — تعطيل فحص أخطاء HTTP
- **المستودع:** `lynomia-chat-app98`
- **الملف:** `chatwoot_api_service.dart:399`
- **السلوك الحالي:** `validateStatus: (status) => true` ⇒ Dio لا يرمي استثناءً أبدًا؛ كل استجابة (401، 403، 429، 500) تصل كنجاح ما لم تُفحص يدويًا — وعدة دوال لا تفحص.
- **السلوك المتوقع:** معالجة صريحة لـ 401 (إعادة تسجيل دخول) و429 (تراجع) و5xx (إعادة محاولة).
- **الخطورة:** **P1**
- **التبعية:** لا شيء
- **الاتجاه:** `Interceptor` مركزي.

### B-10 — لا إعادة مزامنة بعد انقطاع WebSocket
- **المستودع:** `lynomia-chat-app98`
- **الملف:** `chatwoot_api_service.dart:634-680`
- **السلوك الحالي:** بعد `onDone` يُعاد الاتصال بعد 5 ثوانٍ، **لكن لا تُجلب الرسائل الفائتة**.
- **السلوك المتوقع:** إعادة جلب الرسائل منذ آخر رسالة معروفة.
- **الخطورة:** **P1** — **فقدان رسائل صامت** (كارثي لتطبيق دعم عملاء)
- **التبعية:** B-8
- **الاتجاه:** `fetchMessages` بعد كل `confirm_subscription`.

### B-11 — الرمز يُطبع في السجلات
- راجع S-1 في §22.2. **P0.**

### B-12 — كلمة المرور تُرسل إلى نظامين
- راجع S-2 في §22.2. **P0.**

### B-13 — تسجيل OmniAuth مُكرَّر
- **المستودع:** `lynomiachat`
- **الملف:** `config/initializers/devise.rb:251-257` مقابل `config/initializers/omniauth.rb:5-9`
- **السلوك الحالي:** `google_oauth2` مُسجَّل مرتين بخيارات متعارضة. أي middleware يفوز يعتمد على ترتيب تحميل الـ initializers (`devise` قبل `omniauth` أبجديًا) ⇒ سلوك هشّ وغير محدّد في `state` وفي `prompt`.
- **السلوك المتوقع:** تسجيل واحد.
- **الخطورة:** **P1**
- **التبعية:** لا شيء
- **الاتجاه:** حذف الإضافة من `devise.rb` ونقل `prompt: 'select_account'` إلى `omniauth.rb` إن كان مطلوبًا.

### B-14 — لا إلغاء تسجيل FCM عند الخروج
- راجع S-6 في §22.2. **P1.**

---

## 29. Production Blockers — عوائق الإطلاق

### P0 — Blockers (تمنع الإطلاق تمامًا)

| # | العائق | الفئة | المرجع |
|---|---|---|---|
| P0-1 | **رمز الوصول يُطبع في سجلّات الجهاز** | Security / Mobile | S-1 |
| P0-2 | **كلمة المرور تُرسل إلى نطاقين** | Security / Mobile | S-2 |
| P0-3 | **لا فرض حدود ولا Feature Gating** — أي حساب يعمل بلا قيود بغض النظر عن الاشتراك | Business/SaaS | §20.2 |
| P0-4 | **لا جسر بين `lynomia.com` و Chatwoot** — لا webhook، لا مزامنة خطة | Business/SaaS | §20.2 |
| P0-5 | **لا CI/CD ولا بيئة staging؛ التطوير على خادم الإنتاج** | DevOps | D-1, D-2 |
| P0-6 | **`lynomia.com` نظام إنتاجي حرج غير مُدقَّق وغير معروف المستودع** | Infrastructure | D-7 |
| P0-7 | **حالة القنوات الفعلية غير مُتحقَّقة** — لا يمكن الإطلاق بادعاء Omnichannel دون إثبات تشغيلي لكل قناة | Integrations | §13 |

### P1 — Critical (تمنع إطلاقًا موثوقًا)

| # | العائق | الفئة |
|---|---|---|
| P1-1 | تخزين الرموز غير مشفّر في الموبايل (S-3) | Security |
| P1-2 | `validateStatus: true` يُعطّل معالجة الأخطاء (B-9) | Mobile |
| P1-3 | رقم حساب احتياطي `?? 4` (S-5) | Security / Tenancy |
| P1-4 | لا إلغاء FCM عند الخروج (B-14) | Security |
| P1-5 | Sign in with Apple مكسور (B-7) | Mobile / Store |
| P1-6 | لا Pagination (B-8) | Performance |
| P1-7 | لا إعادة مزامنة بعد انقطاع WS — فقدان رسائل (B-10) | Mobile |
| P1-8 | تسجيل OmniAuth مُكرَّر (B-13) | Backend / Auth |
| P1-9 | تسريب CSS عالمي (B-3) | Web / UX |
| P1-10 | كسر i18n + White-labeling (B-4) | Web / UX |
| P1-11 | التعليق الكاذب على WhatsApp (B-1) | Backend |
| P1-12 | قيد `phone_number` الفريد العالمي (S-13) | Database / SaaS |
| P1-13 | الموبايل يفتقد كل إجراءات الوكيل (تعيين/حالة/تصنيفات/ملاحظات/قوالب) | Mobile / Product |
| P1-14 | لا مراقبة ولا تنبيهات (D-5) | DevOps |
| P1-15 | لا نسخ احتياطي موثّق (D-6) | Infrastructure |
| P1-16 | `ENABLE_PUSH_RELAY_SERVER` قد يمنع وصول كل الإشعارات (§19.2) | Notifications |

### P2 — Important

| # | العائق | الفئة |
|---|---|---|
| P2-1 | أيقونات القنوات لا تُطابق في الموبايل (B-6) | Mobile / UX |
| P2-2 | `media_url` مثبّت على Graph v13.0 (S-12) | Integrations |
| P2-3 | Import غير مستخدم يكسر Lint (B-2) | Quality |
| P2-4 | روابط Navbar للجوال 404 (B-5) | Web / UX |
| P2-5 | Telegram token في الـ URL (S-11) | Security |
| P2-6 | `provider_ignores_state: true` (S-10) | Security |
| P2-7 | لا Caching ولا Retry في الموبايل | Performance |
| P2-8 | صفر اختبارات للموبايل | Quality |
| P2-9 | نمو `messages` بلا أرشفة | Scalability |
| P2-10 | `report_rollup` معطّل ⇒ تقارير بطيئة | Performance |

### P3 — Improvement

`local.properties` مُتتبَّع (S-8) · README ووصف `pubspec.yaml` افتراضيان · `dio` v4 · تنظيف الكود الميت في `chatwoot_api_service.dart` · إزالة `chatwoot_client_sdk` · توحيد رسائل الخطأ عبر `AppLocalizations`.

---

## 30. Vision Gap Analysis — تحليل الفجوة مع الرؤية

**المرجع:** Unified Omnichannel Communication & Customer Messaging Platform

| القدرة | الحالة | التفصيل |
|---|---|---|
| **Unified Inbox** | ✅ **Already Exists** | Chatwoot كامل: Inbox موحّد، فلاتر، مجلدات، بحث |
| **Omnichannel** | ⚠️ **Exists but Unverified** | 14 نوع قناة في الكود؛ **صفر إثبات تشغيلي**. يجب التحقق قبل أي ادعاء تسويقي |
| **Team Collaboration** | ✅ **Already Exists** | Teams، Assignment، Private Notes، Mentions، Agent Capacity (EE) |
| **Automation** | ✅ **Already Exists** | Automation Rules، Macros، Auto-resolve، Auto-assignment |
| **AI Agents** | ✅ **Already Exists (EE)** | Captain: Assistants، Documents (pgvector RAG)، Scenarios، Copilot، Tool Registry |
| **Chatbots** | ✅ **Already Exists** | Agent Bots + Webhook bots + Dialogflow integration |
| **Contacts / CRM** | ✅ **Already Exists** | Contacts، Custom Attributes، Contact Notes، Segments، `crm` feature |
| **Campaigns** | ✅ **Already Exists** | One-off + Ongoing، مع `Whatsapp::OneoffCampaignService` |
| **Reports** | ⚠️ **Exists — Needs Upgrade** | تقارير شاملة لكن `report_rollup` معطّل ⇒ أداء ضعيف على البيانات الكبيرة |
| **SLA** | ✅ **Already Exists (EE)** | `SlaPolicy`, `AppliedSla`, `SlaEvent` |
| **Routing** | ✅ **Already Exists** | Round-robin، Team-based، Capacity-based (EE) |
| **Agent Performance** | ✅ **Already Exists** | Agent reports، Conversation metrics، CSAT |
| **Integrations** | ✅ **Already Exists** | Slack، Dialogflow، Linear، Notion، Shopify، Google Translate، Firecrawl، Webhooks |
| **Developer APIs** | ✅ **Already Exists** | Application API + Platform API + Client API + `swagger/` كامل |
| **Webhooks** | ✅ **Already Exists** | Account/Inbox scoped + secrets + HMAC |
| **Mobile App** | ❌ **Exists but Broken / Should Be Reworked** | ~20% من قدرات الوكيل؛ عيوب أمنية P0؛ لا اختبارات؛ دين تقني ثقيل |
| **Enterprise Security** | ⚠️ **Partially Exists** | SAML SSO ✅، MFA ✅، Audit Logs ✅، Custom Roles ✅ — لكن **لا دليل على تفعيل أي منها** |
| **Multi-tenant SaaS** | ⚠️ **Exists but Broken** | العزل التقني ✅ قوي؛ **الطبقة التجارية مفصولة ومكسورة** (§20.2) |
| **Billing / Subscriptions** | ⚠️ **Exists but Bypassed** | Stripe كامل في EE، لكن أُفرغت الواجهة ووُجّهت لنظام خارجي غير مربوط |
| **WhatsApp Flows** | ❌ **Missing** | غير مدعوم في Chatwoot 4.14.1 |
| **White-labeling** | ⚠️ **Exists — Broken by Customization** | آلية Chatwoot كاملة، لكن تخصيص Lynomia تجاوزها بروابط ثابتة |

### الخلاصة الصادمة

**~85% من الرؤية المستهدفة موجود بالفعل في الكود — مجانًا، من Chatwoot.**

الفجوة الحقيقية ليست في الميزات، بل في **ثلاثة أمور فقط**:
1. **التحقق والتهيئة** (Configuration & Verification) — إثبات أن ما هو موجود يعمل فعلًا
2. **الطبقة التجارية** (Commercial Layer) — ربط الدفع بالحدود والميزات
3. **تطبيق الموبايل** — إعادة بناء أو إعادة توجيه

---

## 31. Feature Inventory — جرد الميزات

### موجود ويعمل (موروث، جودة إنتاجية)
Unified Inbox · 14 نوع قناة · Conversations (status/priority/snooze) · Messages (نص/وسائط/صوت/فيديو/ملفات) · Attachments · Private Notes · Mentions · Labels · Custom Attributes · Contacts + CRM · Contact Notes · Segments · Teams · Agents · Inbox Members · Assignment (يدوي/تلقائي/سعوي) · Canned Responses · Macros · Automation Rules · Campaigns · Help Center (Portals/Categories/Articles) · CSAT · Reports (Conversation/Agent/Inbox/Label/Team/Bot) · Audit Logs · Webhooks · Integrations · Agent Bots · Platform API · Application API · Client API · Super Admin · Multi-account · MFA · SAML SSO · Google OAuth · Custom Roles · SLA · Agent Capacity · Captain AI · Copilot · Voice · WhatsApp Calling · Push (FCM/WebPush) · Email notifications · Search (PG/Elastic) · i18n (Crowdin، عشرات اللغات)

### مُخصّص لـ Lynomia
Navbar تسويقي · شعار وخلفية صفحة الدخول · اسم Inbox WhatsApp = رقم الهاتف · إعادة توجيه الفوترة · Google OAuth (مُكرَّر)

### موجود في الموبايل
تسجيل دخول (بريد/Google/Apple‑مكسور) · اختيار Inbox · قائمة المحادثات (فلتر status + inbox) · محادثة (قراءة/إرسال/حذف) · مرفقات · Typing · Realtime · جهات اتصال (إنشاء/بحث/تعديل اسم) · FCM · الخطط والاشتراك والدفع وسجل الدفعات · الشروط والخصوصية · تعدد اللغات · الوضع الداكن

### مفقود كليًا
WhatsApp Flows · جسر الفوترة ↔ الحدود · حدود القنوات/أرقام WhatsApp/التخزين · CI/CD خاص · بيئة staging · مراقبة · وثائق نشر · SDK مشترك بين الويب والموبايل · اختبارات الموبايل

---

## 32. What Must NOT Be Broken — ما يجب ألّا يُكسَر أبدًا

> قائمة حماية إلزامية لأي عمل قادم. **أي تغيير يمس هذه العناصر يتطلّب مراجعة صريحة.**

### 32.1 على مستوى الخادم

| # | العنصر | لماذا |
|---|---|---|
| 1 | **`enterprise/` overlay وآلية `prepend_mod_with`** | تحمل Captain AI، SLA، Custom Roles، SAML، Voice، Capacity. أي تعديل مباشر على ملفات OSS بدلًا من الـ overlay يكسر EE ويُصعّب الـ merge |
| 2 | **كل الـ Migrations الـ 135** | لا تُحذف ولا تُعدّل. أي تعديل يكسر التوافق مع Upstream نهائيًا |
| 3 | **`Current.account` scoping في كل Controller** | خط الدفاع الأول لعزل المستأجرين |
| 4 | **Pundit Policies** | التفويض بالكامل |
| 5 | **تحقق توقيع Webhooks** (`MetaTokenVerifyConcern` وأخواته) | بدونها أي شخص يستطيع حقن رسائل |
| 6 | **`Reauthorizable` + `HealthService`** | تكشف انتهاء الـ tokens؛ "تعطيلها" (كما يوحي التعليق في B-1) يعني قنوات ميتة صامتة |
| 7 | **تشفير `provider_config`** (ActiveRecord Encryption) | يحمي كل مفاتيح Meta/Twilio/360dialog |
| 8 | **`rack-attack`** | الحماية الوحيدة ضد الـ brute force |
| 9 | **ActionCable / `RoomChannel` / `pubsub_token`** | كل الـ realtime في الويب والموبايل |
| 10 | **بنية `Builders → Services → Jobs → Listeners`** | كل منطق القنوات مبني عليها |
| 11 | **`Channel::*` polymorphic على `Inbox`** | أساس الـ Omnichannel كله |
| 12 | **733 Ruby spec + 349 JS spec** | شبكة الأمان الوحيدة الموجودة |

### 32.2 على مستوى المنتج

| # | العنصر | لماذا |
|---|---|---|
| 13 | **بيانات الإنتاج الحالية على `chat.lynomia.com`** | حسابات، محادثات، جهات اتصال حقيقية |
| 14 | **الـ Inboxes المُهيّأة حاليًا** | أي إعادة إنشاء تعني إعادة ربط Meta وفقدان `source_id` |
| 15 | **`webhook_verify_token` لكل قناة WhatsApp** | تغييره يقطع الاستقبال حتى إعادة التسجيل في Meta |
| 16 | **عقد الـ API الذي يعتمده تطبيق الموبايل المنشور** | نسخة `1.0.0+7` قد تكون على أجهزة مستخدمين؛ أي تغيير كاسر يُعطّلها |
| 17 | **`lynomia.com` وتدفق الدفع** | مصدر الإيراد |

---

## 33. Recommended Architecture Direction — الاتجاه المعماري المُوصى به

> المبدأ الحاكم: **Preserve → Repair → Complete → Improve → Modernize**
> **لا Rewrite. لا حذف ميزات.**

### 33.1 القرار الأول: البقاء على Chatwoot كأساس

**التوصية: نعم، بقوة.**

| السبب | التفصيل |
|---|---|
| التخصيص ضئيل | 7 ملفات فقط ⇒ لا "قفل" (lock-in) على fork |
| القيمة الموروثة هائلة | ~85% من الرؤية موجود بالفعل |
| التحديث ممكن وسهل | مسار merge نظيف |
| البديل مستحيل اقتصاديًا | إعادة بناء ما في `enterprise/` وحده تحتاج سنوات فريق |

### 33.2 القرار الثاني: تحويل التخصيصات إلى Overlay

Chatwoot يدعم رسميًا مجلد `custom/` (`lib/chatwoot_app.rb:29-31`, `extensions` تُرجع `%w[enterprise custom]`).

**الاتجاه:**
```
custom/
  app/javascript/...     ← تخصيصات الواجهة
  config/initializers/   ← تخصيصات الإعداد
```
+ استخدام **Chatwoot Custom Branding** (`INSTALLATION_NAME`, `LOGO`, `LOGO_DARK`, `BRAND_URL`, `WIDGET_BRAND_URL`) بدل تعديل الملفات.

**النتيجة:** ملفات التعارض مع Upstream: **من 6 إلى ~1**.

### 33.3 القرار الثالث: توحيد الهوية والفوترة

الوضع الحالي (كلمة مرور واحدة → نظامان) غير قابل للاستمرار. ثلاثة خيارات:

| الخيار | الوصف | التقييم |
|---|---|---|
| **(أ) Chatwoot هو مصدر الحقيقة** | إحياء طبقة Stripe في EE؛ `lynomia.com` يصبح موقعًا تسويقيًا فقط | **الأنظف معماريًا**، لكنه يتطلب هجرة بيانات الاشتراكات |
| **(ب) `lynomia.com` هو مصدر الحقيقة + جسر** | `lynomia.com` يصبح IdP (OAuth/JWT) ويُرسل webhooks لتحديث `Account#limits` و `custom_attributes['plan_name']` في Chatwoot | **الأسرع للإنتاج**، يحافظ على الاستثمار الحالي |
| **(ج) الوضع الراهن** | ❌ **غير مقبول** — لا فرض حدود، وكلمة مرور مزدوجة | مرفوض |

**التوصية: (ب) كمرحلة أولى، مع إبقاء (أ) كهدف بعيد.**
شرط لازم: **لا تُرسل كلمة المرور مرتين أبدًا** — استبدلها بتبادل رمز (token exchange).

### 33.4 القرار الرابع: مصير تطبيق الموبايل

| الخيار | التقييم |
|---|---|
| **(أ) إصلاح تدريجي** | يعالج P0/P1 الأمنية أولًا، ثم يضيف إجراءات الوكيل تدريجيًا. **يحافظ على نسخة المتجر الحالية.** |
| **(ب) إعادة بناء** | لا يُبرَّر: التطبيق صغير (35 ملفًا)، ومعظم المشاكل موضعية |
| **(ج) استخدام تطبيق Chatwoot الرسمي مع Re-brand** | يوفّر 90% من الجهد لكن يفقد شاشات الدفع الحالية |

**التوصية: (أ) — إصلاح تدريجي بترتيب صارم:**
1. **أمن أولًا** (P0-1، P0-2، S-3، S-6)
2. **موثوقية ثانيًا** (B-8، B-9، B-10)
3. **ميزات الوكيل ثالثًا** (الحالة، التعيين، التصنيفات، الملاحظات، قوالب WhatsApp)
4. **تنظيف الدين التقني رابعًا**

مع **طبقة شبكة واحدة**: استخراج `ApiClient` مع Interceptors (auth، retry، 401، 429) وتقسيم `ChatwootApiService` البالغ 2125 سطرًا.

### 33.5 القرار الخامس: عقد API مشترك

المشكلة الجذرية بين المستودعين هي **غياب عقد**. Chatwoot يحتوي `swagger/` كاملًا غير مستغل.

**الاتجاه:** توليد نماذج Dart من OpenAPI ⇒ يمنع أخطاءً كـ B-6 هيكليًا.

---

## 34. Recommended Development Phases — مراحل التطوير المُوصى بها

> **لا تُنفَّذ أي منها الآن.** هذا مقترح ترتيب فقط.

### Phase 1 — التحقق التشغيلي (Operational Verification) — أسبوع واحد
**بلا كتابة كود.**
- استعلامات القراءة على الإنتاج لملء عمود `Production Ready` في §13
- جرد `InstallationConfig` الفعلي (أسماء المفاتيح فقط، لا قيم)
- فحص `ENABLE_PUSH_RELAY_SERVER` و`ACTIVE_RECORD_ENCRYPTION_*` و`CHATWOOT_CLOUD_PLANS`
- **تدقيق `lynomia.com`** — الحصول على المستودع وتدقيقه أمنيًا
- توثيق النشر الحالي

**المخرَج:** مصفوفة Omnichannel نهائية بحالات مؤكّدة + قرار بشأن النظام الثالث.

### Phase 2 — الإصلاحات الأمنية العاجلة — أسبوع إلى أسبوعين
- P0-1، P0-2 (الموبايل: إزالة طباعة الرموز، إنهاء إرسال كلمة المرور المزدوج)
- S-3 (`flutter_secure_storage`)، S-5 (`?? 4`)، S-6 (إلغاء FCM)
- B-13 (OmniAuth المُكرَّر)، B-1 (حذف التعليق الكاذب)
- إصدار موبايل عاجل

### Phase 3 — استقرار المنصة — 2-3 أسابيع
- بيئة **staging** + **CI/CD** حقيقي (P0-5)
- إيقاف التطوير على الخادم مباشرة
- مراقبة (Sentry + APM) + تنبيهات
- نسخ احتياطي موثّق ومُختبَر
- CI لتطبيق الموبايل

### Phase 4 — الطبقة التجارية — 3-4 أسابيع
- جسر `lynomia.com` ⇄ Chatwoot (webhook خطة → `Account#limits`)
- تفعيل `CHATWOOT_CLOUD_PLANS` + `CHATWOOT_CLOUD_PLAN_FEATURES`
- فرض حدود الوكلاء والـ Inboxes
- استبدال تسجيل الدخول المزدوج بتبادل رمز
- حل قيد `phone_number` الفريد العالمي (§12.3)

### Phase 5 — موثوقية الموبايل — 3-4 أسابيع
- Pagination (B-8)، معالجة أخطاء مركزية (B-9)، إعادة مزامنة WS (B-10)
- إصلاح Apple Sign-In (B-7)، أيقونات القنوات (B-6)
- إعادة هيكلة طبقة الشبكة + أول اختبارات

### Phase 6 — إكمال Omnichannel — 4-6 أسابيع
- تهيئة وتوثيق واختبار كل قناة مستهدفة من طرف لطرف
- Runbook لكل قناة (المفاتيح، الموافقات، الاختبار، الاسترجاع)
- قوالب WhatsApp في الموبايل (نافذة 24 ساعة)

### Phase 7 — إجراءات الوكيل في الموبايل — 4-6 أسابيع
- الحالة، التعيين، التصنيفات، الملاحظات، الردود الجاهزة، الإشارات، عدّادات غير المقروء

### Phase 8 — الهوية البصرية والتحديث — 2-3 أسابيع
- نقل التخصيصات إلى `custom/` + Custom Branding
- إصلاح i18n وCSS العالمي
- أول `merge` من Chatwoot upstream على staging

---

## 35. Recommended Launch Roadmap — خارطة طريق الإطلاق

| المرحلة | المدة التقديرية | البوابة (Gate) — لا يُتجاوَز إلا بتحققها |
|---|---|---|
| **G0 — التحقق** | أسبوع | مصفوفة القنوات مكتملة بحالات مؤكّدة؛ `lynomia.com` مُدقَّق |
| **G1 — Security Clear** | +2 أسبوع | صفر P0 أمني؛ إصدار موبايل عاجل منشور |
| **G2 — Ops Clear** | +3 أسابيع | staging يعمل؛ CI/CD يعمل؛ المراقبة تُنبّه؛ نسخة احتياطية مُستعادة بنجاح مرة واحدة على الأقل |
| **G3 — Commercial Clear** | +4 أسابيع | حساب غير مدفوع **يُمنع فعليًا** من تجاوز حدوده — مُثبَت باختبار |
| **G4 — Mobile Reliable** | +4 أسابيع | لا فقدان رسائل بعد انقطاع شبكة؛ Pagination تعمل على حساب بـ 1000+ محادثة |
| **G5 — Omnichannel Proven** | +6 أسابيع | كل قناة معلنة تجتاز اختبار end-to-end موثّق (إرسال + استقبال + حالة) |
| **G6 — Soft Launch** | +2 أسبوع | 5-10 عملاء حقيقيين تحت مراقبة لصيقة |
| **G7 — General Availability** | +4 أسابيع | استقرار مُثبَت؛ SLA داخلي مُعرَّف؛ خطة دعم قائمة |

**الإجمالي التقديري حتى GA: 6-7 أشهر** بفريق مُكرَّس.

### قاعدة الإطلاق الذهبية

> **لا تُعلن أي قناة في التسويق قبل أن تجتاز اختبار end-to-end موثّقًا على الإنتاج.**
>
> وجود الكود ≠ قناة تعمل. هذه هي الرسالة المركزية لتقرير Phase 0.

---

## الإجابات المباشرة على أسئلة Phase 0

| السؤال | الجواب |
|---|---|
| **ما الموجود؟** | Chatwoot 4.14.1 Enterprise شبه نقي + 7 ملفات تخصيص + تطبيق Flutter بـ35 ملفًا + نظام ثالث مجهول على `lynomia.com` |
| **ما الذي يعمل؟** | كل ما ورثناه من Chatwoot يعمل **على مستوى الكود**. التطبيق يسجّل الدخول ويعرض ويرسل الرسائل. التخصيص الوظيفي الوحيد الذي يعمل هو تسمية Inbox الواتساب برقم الهاتف. |
| **ما الذي لا يعمل؟** | فرض الحدود والاشتراكات (غير موجود أصلًا) · Apple Sign-In · أيقونات القنوات في الموبايل · i18n في صفحة الدخول · الـ Lint · "تثبيت اتصال WhatsApp" (لم يُنفَّذ قط) |
| **ما الذي تم تخصيصه؟** | 7 ملفات، أقل من 0.05% من الكود: Navbar، صفحة الدخول، إعادة توجيه الفوترة، اسم Inbox الواتساب، Google OAuth |
| **ما الذي ورثناه من Chatwoot؟** | **كل شيء آخر** — كل القنوات، كل الخدمات، كل قاعدة البيانات، كل الـ Enterprise (Captain AI، SLA، Custom Roles، SAML، Voice)، كل الاختبارات، كل الـ CI |
| **هل Lynomia Chat حاليًا Omnichannel فعليًا؟** | **قدرةً: نعم — 14 نوع قناة كاملة في الكود.** **إثباتًا: لا — لا يوجد أي دليل في المستودع على أن أي قناة مُهيّأة وتعمل في الإنتاج.** والموبايل لا يميّز القنوات بصريًا بسبب خطأ مؤكّد. |
| **ما القنوات الجاهزة؟** | جاهزة **بالكود**: WhatsApp (Cloud + 360dialog)، Facebook، Instagram، Telegram، LINE، Email، Website، SMS (Twilio + Bandwidth)، API، TikTok، Voice. **الجاهزية التشغيلية تتطلب Phase 1.** |
| **ما القنوات غير الجاهزة؟** | **X/Twitter** — مُهلَك ومحذوف من الواجهة. **WhatsApp Flows** — غير مدعوم. **TikTok** — مخفي ما لم يُهيّأ. |
| **ما الذي يمنع الإطلاق؟** | 7 عوائق P0: عيبان أمنيان في الموبايل · غياب فرض الحدود · غياب جسر الفوترة · غياب CI/CD وstaging · نظام ثالث غير مُدقَّق · حالة القنوات غير مُثبَتة |
| **ما الترتيب الصحيح؟** | تحقق ← أمن ← بنية تحتية ← تجاري ← موثوقية الموبايل ← إثبات القنوات ← ميزات ← إطلاق. **مفصّل في §34 و§35.** |

---

## ملاحظة ختامية

هذا التقرير **لم يعدّل سطرًا واحدًا من الكود**. كل النتائج مدعومة بمواقع ملفات وأرقام أسطر قابلة للتحقق.

**الخبر الجيد:** المشروع في وضع أفضل بكثير مما توحي به التقارير السطحية — لأن 85% من الرؤية موجود فعلًا، ومسار التحديث من Upstream سالك.

**الخبر الصعب:** ما ينقص ليس ميزات، بل **الإثبات والتهيئة والانضباط الهندسي** — وهذه لا تُشترى بكود، بل ببوابات جودة.

**في انتظار مراجعتك وأمر الانتقال إلى المرحلة التالية.**
