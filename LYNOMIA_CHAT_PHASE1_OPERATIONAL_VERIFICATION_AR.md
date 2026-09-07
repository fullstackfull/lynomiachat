# تقرير Phase 1 — التحقق التشغيلي واكتشاف النظام وتثبيت المعمارية
# Lynomia Chat — Phase 1: Operational Verification, System Completion Discovery & Architecture Lock

**تاريخ التنفيذ:** 2026-09-07 / 2026-09-08
**الترتيب المتبع:** VERIFY → MAP → TEST → SECURE → DECIDE → PLAN
**تعديلات الكود:** إصلاحان أمنيان فقط في تطبيق الموبايل (P0-1)، موثّقان في §12. لا تعديل معماري، لا Rewrite، لا Upstream Merge، لا تغيير قاعدة بيانات.

---

## ⚠️ 0. إفصاح إلزامي عن حدود هذه المرحلة — اقرأه قبل أي شيء

طلبتَ صراحةً: **«ممنوع إعلان اكتمال زائف»** و**«لا تخمّن»**. لذلك أبدأ بما **لم** أستطع التحقق منه.

### 0.1 ما هو محجوب تمامًا (BLOCKED)

| القدرة | الحالة | الدليل |
|---|---|---|
| الوصول الشبكي إلى `lynomia.com` | ❌ **محجوب** | `curl: (56) CONNECT tunnel failed, response 403` |
| الوصول الشبكي إلى `chat.lynomia.com` | ❌ **محجوب** | نفس الخطأ |
| قاعدة بيانات الإنتاج | ❌ غير متاحة | `pg_isready 127.0.0.1:5432 → no response` |
| تشغيل Rails | ❌ | `rails` غير مثبّت؛ Ruby 3.3.6 بينما المشروع يتطلب 3.4.4 |
| تشغيل PHP/Laravel | ❌ | لا PHP، لا `composer install`، لا `vendor/` |
| تشغيل Flutter | ❌ | `flutter` و `dart` غير مثبّتين |
| Redis / Sidekiq / ActionCable | ❌ | لا خدمات تعمل |

### 0.2 الأثر المباشر على ما طلبته

| القسم المطلوب | ما أمكن تنفيذه فعليًا |
|---|---|
| §5 Production Configuration Audit | ❌ **لا يمكن تنفيذه.** بديلًا: قائمة تحقق دقيقة وقابلة للتنفيذ (§6) |
| §6 Omnichannel Production Verification | ❌ **لا يمكن تنفيذه.** بديلًا: مصفوفة شروط + إجراء تحقق (§7) |
| §7 End-to-End Channel Test Matrix | ❌ **لا يمكن تنفيذه.** بديلًا: إجراء اختبار آمن جاهز للتشغيل (§8) |
| §8 WhatsApp Verification | ⚠️ **تشغيليًا: لا.** لكن اكتُشفت معمارية WhatsApp الحقيقية وهي مختلفة جذريًا (§9) |
| §9 Mobile Runtime Verification | ⚠️ **تشغيليًا: لا.** أُنجز Baseline ساكن شامل بدلًا منها (§10) |
| §10-11 P0 Security Containment | ✅ **نُفِّذ جزئيًا** — راجع §12 بدقّة، بما فيه إقرار بخطأ ارتكبته |
| §2 اكتشاف النظام الثالث | ✅ **نجح بالكامل** — النظام وُجِد ودُقِّق |

**القاعدة المطبقة في كل هذا التقرير:** كل عبارة إمّا مدعومة بـ `ملف:سطر` قرأتُه، أو موسومة صراحةً بـ `UNVERIFIED` أو `BLOCKED`.

### 0.3 المنهجية

12 وكيلًا متخصصًا بنطاقات منفصلة (لا تكرار قراءة)، أنتجوا **178 نتيجة** (24 P0 / 70 P1 / 60 P2 / 24 P3)، ثم مراجعة عدائية مستقلة متعددة العدسات للنتائج الحرجة. **من أول 6 نتائج خضعت للمراجعة المستقلة، دُحِضت 2 (33%)** — وهذا وحده يثبت ضرورة ما طلبتَه في §22. كما دُحِض جزئيًا استنتاج توصّلتُ إليه بنفسي (§5.4).

---

## 1. Phase 0 Findings Status — حالة نتائج المرحلة صفر

### 1.1 التصحيحات الجوهرية لتقرير Phase 0

اكتشاف النظام الثالث غيّر الصورة جذريًا. أُصحّح سجلّي:

| # | ما قاله Phase 0 | الحكم | الحقيقة المُثبتة |
|---|---|---|---|
| P0-4 | «لا يوجد أي جسر بين lynomia.com و Chatwoot في الكود» | ❌ **خاطئ تمامًا** | يوجد جسر ثنائي الاتجاه، موقّع بـ HMAC، بحماية Replay، وطبقة Connectors كاملة. §5 |
| P0-3 | «لا فرض حدود إطلاقًا» | ⚠️ **خاطئ جزئيًا** | حدود الوكلاء والـ Inboxes **تُكتب وتُحترم فعليًا**. تعطيل الميزات هو المكسور، لا الحدود. §5.4 |
| P0-5 | «لا CI/CD في أي مكان» | ⚠️ **خاطئ جزئيًا** | `lynomia98` لديه CI حقيقي (`virtual-staging.yml`) ببوابتَي secret-hygiene و tls-hygiene. Chatwoot والموبايل: لا يزال صحيحًا. |
| — | «التطوير يتم على خادم الإنتاج» | ✅ **صحيح ومؤكَّد** | مؤلف `7bb7e5d8` هو `root@server2.lynomia.com` |
| — | «WhatsApp = Meta Cloud API + Embedded Signup» | ❌ **مضلِّل** | المسار الإنتاجي الفعلي هو **Zender → Central → Chatwoot API-channel**. §9 |
| — | توصية «نقل التخصيصات إلى `custom/`» | ❌ **غير قابلة للتنفيذ** | `custom/` **hook ميت** في 4.14.1: لا يحمّل Ruby ولا Vue. §18 |
| S-2 | «كلمة المرور تُرسل إلى نظامين» | ✅ صحيح، **وأسوأ** | يُضاف إليها تسريب رأس `Authorization` الخاص بـ Chatwoot إلى lynomia.com. §11 |
| B-1 | «تعليق WhatsApp كاذب» | ✅ **مؤكَّد** | والأثر أدق: الـ webhooks الواردة تُسقَط بصمت عند `reauthorization_required` |

### 1.2 سجل القضايا (Issue Registry) — البنية

كل نتيجة في هذا التقرير تحمل الحقول التي طلبتَها:
`ID · Severity · Repository · File:Line · Current · Expected · Production impact · Verification method · Dependency · Fix phase · Regression risk`

السجل الكامل في §19. الأرقام الإجمالية:

| المستودع | P0 | P1 | P2 | P3 | المجموع |
|---|---|---|---|---|---|
| `lynomia98` (Central) | 14 | 38 | 27 | 11 | 90 |
| `lynomia-chat-app98` (Mobile) | 6 | 17 | 14 | 6 | 43 |
| `lynomiachat` (Chatwoot) | 4 | 15 | 19 | 7 | 45 |
| **المجموع** | **24** | **70** | **60** | **24** | **178** |

---

## 2. Third Backend Discovery — اكتشاف النظام الثالث ✅

### 2.1 وُجِد

| البند | القيمة |
|---|---|
| **Repository** | **`fullstackfull/lynomia98`** |
| **Branch** | `main` — آخر commit `609bf06` (2026-09-08) |
| **الاسم الداخلي** | **Lynomia Central Account** |
| **Framework** | Laravel **13.8** / PHP **8.3+** |
| **Auth** | Laravel **Sanctum 4.0** |
| **Payments** | `stripe/stripe-php ^20.2` + **Paymera** (مزود إقليمي) |
| **الحجم** | 183 ملف PHP · 31 Controller · 26 Model · 52 Migration |
| **التوثيق** | **141 ملف Markdown** من تدقيقات وتنفيذ سابقة (Phases A→G1) |
| **CI** | `.github/workflows/virtual-staging.yml` — حقيقي ويعمل |

### 2.2 كيف عُثِر عليه

عبر `list_repos` على الحساب، ثم مطابقة مسارات النهايات التي يستدعيها تطبيق Flutter مقابل `routes/api.php`. **تطابق مؤكَّد:**

| المسار الذي يستدعيه تطبيق Chat | موقعه في `lynomia98` |
|---|---|
| `POST /api/register/google` | `routes/api.php:87` |
| `POST /api/auth/apple/signup` | `routes/api.php:47` |
| `POST /api/chat/mobile-checkout` | `routes/api.php:81` |
| `GET /api/chat/subscription` | `routes/api.php:100` |
| `GET /admin/subscriptions/{id}` | `routes/web.php:485` |
| `POST /api/verify-google-play-purchase` | ❌ **غير موجود** — راجع §5.6 |

### 2.3 الاكتشاف الأكبر: ليست ثلاثة أنظمة، بل منظومة كاملة

`lynomia98` ليس «باك-إند الدفع لـ Chat». إنه **الحساب المركزي لمنظومة منتجات Lynomia بأكملها**:

| # | المستودع | المنتج | الحالة |
|---|---|---|---|
| 1 | `lynomia98` | **Central** — الهوية، الفوترة، التزويد، SSO، الإدارة | المركز |
| 2 | `qr_lynomai98` | Lynomia QR | مُدمج |
| 3 | `otp_lynomai98` | Lynomia OTP — منصة **Zender** (بوابة SMS/WhatsApp) | مُدمج |
| 4 | `social_lynomai89` | Lynomia Social | مُدمج |
| 5 | **`lynomiachat`** | **Lynomia Chat** (Chatwoot) | مُدمج |
| 6 | `cloud` | Lynomia Cloud | **غير مُدمج** |
| 7 | `syriastore98` | Syria Store | **غير مُدمج** |
| 8-11 | أربعة تطبيقات Flutter | QR / OTP / Social / **Chat** | عملاء |

**الأثر:** أي قرار معماري بشأن الهوية أو الفوترة في Lynomia Chat **يمسّ أربعة منتجات**، لا منتجًا واحدًا. مصدر: `docs/cross-repo-audit/CONNECTED_REPOSITORIES.md`.

### 2.4 حقيقة تشغيلية حاسمة: الكود المُدقَّق ليس هو الكود المنشور 🔴

تقرير الإغلاق الخاص بالمستودع نفسه، حرفيًا (`docs/implementation/PHASE_A_OPERATIONAL_CLOSURE_REPORT.md:254-256`):

> **"Nothing deployed, nothing rotated, no history rewritten → current production is byte-for-byte the pre-Phase-A state."**

`lynomia98` خضع لسبع مراحل تحصين (A→G1) دُمجت كلها في `main` خلال 2026-09-07. **لكن لا شيء منها مُطبَّق على الإنتاج.**

**الأثر:** كل ما هو مُصلَح في هذا التقرير (مصادقة الإدارة، حذف نقطة كشف كلمة المرور، تشفير الاعتمادات) **قد يكون ما زال مكشوفًا في الإنتاج**. حالة: `UNVERIFIED — لا وصول للإنتاج`. طريقة الحسم: `git rev-parse HEAD` + `php artisan migrate:status` على الخادم.

---

## 3. Full System Architecture — المعمارية الكاملة

```
                        ┌──────────────────────────────────────┐
                        │   عميل / وكيل                        │
                        └───────┬──────────────────┬───────────┘
                    تطبيق Flutter            متصفح الويب
                                │                  │
        ┌───────────────────────┼──────────────────┼────────────────────┐
        ▼                       ▼                  ▼                    ▼
┌────────────────┐   ┌─────────────────────────────────────┐   ┌────────────────┐
│ chat.lynomia   │   │      lynomia.com — CENTRAL          │   │  otp.lynomia   │
│ .com           │   │      Laravel 13.8 + Sanctum         │   │  (Zender)      │
│ Chatwoot       │   │                                     │   │  بوابة WhatsApp │
│ 4.14.1 EE      │   │  • الهوية (users, google_accounts,   │   └───────┬────────┘
│                │   │    apple_accounts)                  │           │
│ • المحادثات    │   │  • الفوترة (Stripe + Paymera)        │           │
│ • القنوات      │   │  • التزويد على 4 منتجات              │           │
│ • الوكلاء      │   │  • SSO Launcher                     │           │
└───┬────────┬───┘   │  • كونسول الإدارة                    │           │
    │        │       └──────┬──────────────────┬───────────┘           │
    │        │              │                  │                       │
    │        │  Platform API│         Application API                  │
    │        │  (PlatformApp token)   (createInbox)                    │
    │        │              │                  │                       │
    │        └──────────────┘                  │                       │
    │         PATCH /platform/api/v1/accounts/{id}                     │
    │           {limits, features, status}                             │
    │                                                                   │
    │   ┌───────────────────────────────────────────────────────────┐  │
    └──▶│  جسر الرسائل — نصّي فقط                                     │◀─┘
        │  IN : Zender ──▶ POST /api/webhook/zender    (secret)      │
        │  OUT: Chatwoot ─▶ POST /api/chatwoot-webhook (HMAC-SHA256) │
        └───────────────────────────────────────────────────────────┘
```

**النتيجة:** ليست «ثلاثة أنظمة» بل **أربعة في مسار رسالة WhatsApp الواحدة**: العميل ↔ Zender ↔ Central ↔ Chatwoot.

---

## 4. Identity Architecture — معمارية الهوية

### 4.1 مصدر الحقيقة — الجدول الحاسم

| العنصر | مصدر الحقيقة اليوم | الدليل |
|---|---|---|
| **هوية المستخدم** | **Central** (`lynomia98.users`) | Central يُنشئ مستخدم Chatwoot عبر `POST /platform/api/v1/users` — `ChatwootConnector.php:93` |
| **البريد** | **Central** | نفس المرجع |
| **كلمة المرور** | ⚠️ **مُكرَّرة في 4 أنظمة** | `PlatformProvisioning` يزوّد نفس كلمة المرور المولَّدة إلى QR/OTP/Social/Chat |
| **Company / Organization** | **Central** (Phase F) | لكن **بلا أي سطح HTTP** — 12 جدولًا و13 Gate لا يستدعيها شيء (P1) |
| **Chatwoot Account** | **Central يُنشئه** | `ChatwootConnector.php:106` — **غير idempotent**: كل إعادة محاولة تُنشئ حسابًا يتيمًا |
| **الاشتراك** | **Central** | `billing_subscriptions` + `accounts_subscriptions_chat` |
| **Role (داخل Chatwoot)** | **Chatwoot** | `account_users.role` |
| **Entitlements** | **Central يكتبها، Chatwoot ينفّذها** | §5 |

**الجواب على سؤالك:** **Central هو مصدر الحقيقة للهوية.** Chatwoot تابع (downstream)، ويُدار عبر Platform API.

### 4.2 التدفق الفعلي (Email + Password) — متتبَّع بالكود

```
1. Flutter → POST chat.lynomia.com/auth/sign_in {email, password}
     ← {access_token, account_id, pubsub_token, id}          [chatwoot_api_service.dart:991]
2. Flutter يضبط على الـ Dio المشترك:
     api_access_token = <chatwoot token>
     Authorization    = Bearer <chatwoot token>              [:1023-1024]
3. Flutter → POST lynomia.com/api/login {email, password}    [:1053]  ← نفس الـ Dio!
     ← {access_token: <Sanctum PAT>}
4. Flutter → POST chat.lynomia.com/api/v1/notification_subscriptions {fcm}
```

**عيبان مثبتان في الخطوتين 2-3:**
- **P0** — لأن الطلب في الخطوة 3 يستخدم **نفس نسخة Dio**، تُرسَل رؤوس `api_access_token` و`Authorization` الخاصة بـ Chatwoot **إلى lynomia.com**. أي أن Laravel وسجلّاته وبروكسيه يستقبلون رمز وكيل Chatwoot حيًّا في كل تسجيل دخول. (`chatwoot_api_service.dart:393-400, 1023-1024, 1032`)
- **P0** — كلمة المرور تُرسل إلى نظامين.

### 4.3 تدفّق Google / Apple — ثغرات استيلاء على الحسابات 🔴

| # | النتيجة | الملف | الخطورة |
|---|---|---|---|
| ID-01 | **`POST /api/register/google` لا يتحقق من أي ID token إطلاقًا.** العقد يقبل `name/email/google_id` كنصوص فقط. لا JWKS، لا `aud`، لا `iss`. | `GoogleRegisterController.php:109-144`، `routes/api.php:87` | **P0** |
| ID-02 | **`POST /api/auth/apple/signup` لا يتحقق من توقيع identityToken**، والرمز **اختياري أصلًا**. `decodeAppleIdentityToken` يفكّ base64 للمقطع الأوسط ويفحص `exp` فقط. | `AppleRegisterController.php:24-56, 224-336`، `routes/api.php:47` | **P0** |
| ID-03 | **`config('services.platform_secret')` غير معرَّف.** كلمة المرور عبر المنصات = `hash_hmac('sha256', $user->email, null)` ⇒ **مفتاح فارغ** ⇒ قابلة للحساب من البريد وحده. | `GoogleRegisterController.php:97`، `AppleRegisterController.php:120,210`، `config/services.php` (106 سطرًا، بلا المفتاح) | **P0** |

**الأثر المركّب:** طلب HTTP واحد غير مُصادَق + معرفة بريد الضحية ⇒ رمز Sanctum صالح + كلمة مرور المنصات (المشتركة عبر أربعة منتجات) + استجابة تسجيل دخول Chatwoot. **استيلاء كامل على الحساب عبر المنظومة.** ولا يوجد `throttle` على أيٍّ من المسارين.

### 4.4 المعمارية النهائية المقترحة — هوية واحدة

**المبدأ الملزم الذي طلبتَه:** لا تُرسَل كلمة مرور المستخدم إلى نظامين أبدًا.

```
                     ┌────────────────────────────────┐
                     │  Central = مزوّد الهوية الوحيد  │
                     │  (Identity Provider)           │
                     └───────────────┬────────────────┘
   1. تسجيل الدخول مرة واحدة          │
   Flutter ─────────────────────────▶ │  POST /api/login {email, password}
                                      │  + id_token عند Google/Apple (مُتحقَّق منه)
                     ◀────────────────┘  ← Sanctum PAT (بصلاحيات محدودة + انتهاء)
   2. تبادل الرمز (لا كلمة مرور)
   Flutter ─────────────────────────▶ Central: POST /api/sso/chat
                                      │  Central → Chatwoot Platform API:
                                      │  GET /platform/api/v1/users/{id}/login
                     ◀────────────────┘  ← رابط SSO موقّع صالح 5 دقائق
   3. Flutter يستبدله برمز Chatwoot ويستخدمه للمحادثات فقط.
```

**الخبر الجيد — البنية موجودة بالفعل:** `ChatwootConnector::ssoUrl()` (`ChatwootConnector.php:177-200`) ينفّذ بالضبط `GET /platform/api/v1/users/{id}/login` **بلا أي كلمة مرور**. ووثيقة `PHASE_C_SSO_MIGRATION_REPORT.md` تؤكد أن هذا التحوّل تم بالفعل للويب. **الناقص هو فقط تعريضه للموبايل عبر نقطة نهاية `/api/sso/chat`.**

**خطة الترحيل بأدنى مخاطرة (لا تُنفَّذ الآن):**
1. إضافة `POST /api/sso/chat` في Central (خلف `auth:sanctum`) تُعيد رابط SSO — **إضافة فقط، لا كسر**.
2. إصدار موبايل يستخدمها؛ الإبقاء على `_loginToLynomia` كـ fallback.
3. بعد تبنّي ≥95% من المستخدمين: حذف `_loginToLynomia`.
4. عزل نسخة Dio لـ Central فورًا (إصلاح مستقل، آمن، يزيل تسريب الرأس).

> **⚠️ لا تحذف `_loginToLynomia()` الآن.** رمز Sanctum الناتج هو ما تستخدمه شاشات الدفع (`payment_api_service.dart` × 4 نقاط). حذفه يكسر الدفع فورًا. هذا يطابق تحذيرك في §10.

---

## 5. SaaS / Billing Architecture — الطبقة التجارية

### 5.1 الجسر موجود — تصحيح كامل لـ Phase 0

**Phase 0 قال: «لا يوجد جسر». هذا خطأ.** الجسر موجود ومُهندَس جيدًا:

| الاتجاه | النقطة | المصادقة | الحالة |
|---|---|---|---|
| Central → Chatwoot | `PATCH /platform/api/v1/accounts/{id}` | PlatformApp token | ✅ يعمل |
| Central → Chatwoot | `POST /platform/api/v1/users` (upsert بالبريد) | PlatformApp token | ✅ idempotent |
| Central → Chatwoot | `GET /platform/api/v1/users/{id}/login` (SSO) | PlatformApp token | ✅ بلا كلمة مرور |
| Chatwoot → Central | `POST /api/chatwoot-webhook` | **HMAC-SHA256** + Replay protection | ✅ مُحكم |
| Zender → Central | `POST /api/webhook/zender` | سرّ مشترك + `hash_equals` | ✅ زمن ثابت |

**جودة عالية مؤكَّدة:** `VerifyChatwootWebhookSignature.php` يتحقق من `X-Chatwoot-Signature` = `sha256=HMAC(secret, "{timestamp}.{body}")`، و`WebhookDelivery::claim()` يمنع التكرار عبر قيد فريد على `X-Chatwoot-Delivery`.

### 5.2 ماذا يحدث فعليًا عند الدفع

```
Stripe webhook → StripeEventProcessor → BillingSettlementService::settlePaid
     ├─ يُثبِّت: payment=PAID, invoice=PAID, subscription=ACTIVE   ← يُنفَّذ أولًا
     └─ ثم: BillingFulfillmentService::fulfill
              └─ ChatPlanActivator::buildParams  ← BillingCatalog::chatActivation
                     └─ ChatwootConnector::updateAccount
                            └─ PATCH /platform/api/v1/accounts/{id}
                                   {limits:{agents,inboxes}, features:{...}, status}
```

### 5.3 هل تحترم Chatwoot ما يكتبه Central؟ — تحقق مباشر ✅

تتبّعتُ ذلك بنفسي عبر المستودعين:

| الحلقة | النتيجة | الدليل |
|---|---|---|
| Chatwoot يسمح بالحقول؟ | ✅ `params.permit(:name,:locale,:domain,:support_email,:status, features:{}, limits:{}, custom_attributes:{})` | `platform/api/v1/accounts_controller.rb:47` |
| `limits` تُحفظ؟ | ✅ في عمود `limits` (jsonb) | `:19` |
| هل تُقرأ فعلًا؟ | ✅ `get_limits` يقرأ `self[:limits][name]` **أولًا** | `enterprise/.../plan_usage_and_limits.rb` |
| `status: suspended` صالح؟ | ✅ `enum :status, {active:0, suspended:1}` | `account.rb:106` |

**⇒ حدود الوكلاء والـ Inboxes والتعليق تعمل فعليًا.** Phase 0 كان مخطئًا في هذا.

### 5.4 لكن تفعيل الميزات مكسور — وهنا صحّحتُ نفسي 🔴

**ما ادّعيتُه أولًا (وكان خاطئًا):** أن Central يرسل `features` كمصفوفة بينما Chatwoot يتوقع hash، فلا يحدث شيء.

**المراجعة العدائية المستقلة (3 عدسات) دحضت ذلك جزئيًا:** `ChatwootConnector::featuresHash()` **يُطبِّع المصفوفة إلى hash فعلًا** (إصلاح Phase C.1). كنتُ مخطئًا. **الشكل سليم.**

**الحقيقة الأدق — والأسوأ:** المشكلة في **أسماء الميزات**، ويوجد **أربعة مسارات تفعيل بمفردات متضاربة**، ولا شيء يتحقق من الأسماء مقابل `features.yml`:

| المسار | الأسماء المُرسلة | النتيجة |
|---|---|---|
| **A. الكتالوج** (مسار Stripe المدفوع الحقيقي)<br>`BillingCatalog.php:70-73` | `startup` → `channel_website` | ✅ **صالح — يعمل بالكامل** |
| | `growth` → `+ channel_api` | ❌ `channel_api` **ليس ميزة Chatwoot** |
| | `enterprise` → `+ channel_email` | ❌ ينهار على `channel_api` |
| **B. كونسول الإدارة**<br>`ChatwootSubscriptionController.php:94-106` | `channels`, `advanced_reports`, `custom_channels`, `ai_features` | ❌ **4 من 6 غير موجودة** |
| **C. التسجيل / التجربة**<br>`PlatformRegisterController.php:1307-1352` | نفس القائمة المخترعة | ❌ **يكسر كل حساب جديد** |
| **D. Paymera + الوظيفة المجدولة** | **حدود فقط، بلا `features`** | ✅ **يعمل** (`array_key_exists` يُسقط الحقل) |

**التحقق من الأسماء** (نفّذتُه بنفسي مقابل `lynomiachat/config/features.yml`):

| الاسم | موجود؟ |
|---|---|
| `channel_website`, `channel_email`, `canned_responses`, `integrations` | ✅ |
| `channel_api`, `channels`, `advanced_reports`, `custom_channels`, `ai_features` | ❌ **غير موجودة** |

**الآلية:** `enable_features(name)` → `send("feature_#{name}=", true)`. FlagShihTzu يُولّد الـ setters **فقط** لأسماء `features.yml`. اسم غير معروف ⇒ `NoMethodError`. وترتيب `accounts_controller.rb:19-21` هو `assign_attributes` → `update_resource_features` → `save!` ⇒ **الاستثناء يقع قبل `save!` فلا يُحفظ شيء: لا الحدود ولا الحالة.**

**النتيجة النهائية المُصحَّحة (إجماع 3 مراجعين مستقلين):**
- خطة `startup` المدفوعة: ✅ تعمل
- خطتا `growth` و`enterprise`: ❌ العميل **يُخصَم منه** وCentral يسجّله **ACTIVE** ولا يصل Chatwoot شيء
- مسار التجربة/التسجيل: ❌ مكسور لكل الخطط
- التعليق (`suspended`): ✅ يعمل
- **الخطورة المُصحَّحة: P1 لا P0** (لأن startup تعمل، والفشل يُسجَّل كـ `billing_fulfillments = FAILED` ولا يُبلَّغ كنجاح)

**لماذا لم يكتشفه أحد:** `tests/Support/Simulators/ChatwootSimulator.php:181` يُرجِع 200 لأي اسم ميزة بلا تحقق. صفر اختبار يقرأ `features.yml` الحقيقي.

### 5.5 العيب التجاري الأكبر: الاستحقاق سقّاطة أحادية الاتجاه 🔴 P0

`BillingSettlementService::settleFailed()` (`:95-113`) يضع الدفعة FAILED والاشتراك PAYMENT_FAILED **ثم يعود**. لا يستدعي Fulfillment، لا Connector، لا PATCH.

و`ChatPlanActivator` لا يرسل إلا `status=active`.

**⇒ لا يوجد أي مسار كود يُعلّق أو يُخفّض أو يُقيّد حساب Chatwoot عند توقف الدفع.** كل من دفع مرة واحدة يحتفظ بحدوده كاملة إلى الأبد. **صفر حماية للإيراد.**

(القدرة موجودة — `updatePlan` يدعم `suspended` ويعمل — لكن **لا شيء يستدعيها تلقائيًا**.)

### 5.6 عيوب تجارية إضافية مؤكَّدة

| ID | النتيجة | الملف | الخطورة |
|---|---|---|---|
| BI-01 | **اشتراكات Chat المدفوعة بـ Stripe لا تصبح `active` أبدًا.** كلا مدخلَي الدفع يُدرجان `status='pending'`، والكاتبان الوحيدان لـ `'active'` هما مسارا Paymera. `GET /api/chat/subscription` يتطلب `active` ⇒ يُرجع 404 «لا اشتراك» لعميل دافع. | `ChatwootSubscriptionController.php:50-56,159-165` | **P0** |
| BI-02 | **`STRIPE_WEBHOOK_SECRET` يُقرأ بـ `env()` بلا مفتاح config.** تحت `php artisan config:cache` يعود `null` ⇒ **كل webhook يُرفض بـ 400** ⇒ Stripe يُعطّل النقطة. | `StripeGateway.php:29-32` | **P0** |
| BI-03 | **`POST /api/verify-google-play-purchase` غير موجود في Central** بينما تطبيق Chat يستدعيه ⇒ 404 ⇒ مشتريات Google Play لا تُتحقَّق. والتطبيق **يُقرّ الشراء قبل التحقق**. | `payment_api_service.dart:135` مقابل `routes/api.php` | **P1** |
| BI-04 | **`GET /api/chat/subscription` غير مُصادَق** ويكشف اشتراك أي مستخدم بالبريد. | `routes/api.php:100` | **P1** |
| BI-05 | **`POST /api/my/payment/{platform}` يُرجع سجل دفعات أي مستخدم** بمعرّف من العميل. | `routes/api.php:64` | **P1** |
| BI-06 | **`GET /api/plans/chat` يُرجع كائنًا فارغًا** (`JsonResponse` داخل `json()`) ⇒ شاشة الخطط في الموبايل فارغة. | `PlatformPlansController.php` | **P1** |
| BI-07 | **حدود متضاربة حسب مسار الدفع:** Stripe يمنح 100 وكيل حيث تمنح المسارات الأخرى 15. | `BillingCatalog.php:67-75` | **P1** |
| BI-08 | **زر الفوترة في Chatwoot يُرسل كل مدير حساب إلى رابط إداري في Central** (`/admin/subscriptions/{id}` خلف `admin.area`) ⇒ **لا توجد قناة شراء ويب للعميل إطلاقًا**. | `billing/Index.vue:8-10` ← `routes/web.php:483` | **P1** |

### 5.7 طبقة المزامنة المقترحة: Subscription → Entitlement

**لا تُنفَّذ الآن.** التصميم المطلوب — ويُبنى على ما هو موجود بالفعل:

```
حدث الدفع (Stripe/Paymera)
   │
   ▼
BillingSettlementService  ──── settlePaid ────┐
   │                                          │
   └──── settleFailed / expired / cancelled ──┤   ← الناقص اليوم
                                              ▼
                            ┌──────────────────────────────┐
                            │  EntitlementReconciler       │  ← جديد
                            │  (مصدر الحقيقة: الاشتراك)     │
                            │  • idempotent بمفتاح مطالبة   │
                            │  • جدول تحقق من الأسماء       │
                            │    مقابل features.yml         │
                            │  • Audit log لكل تغيير        │
                            │  • Retry بتراجع أسّي           │
                            └──────────────┬───────────────┘
                                           ▼
                       ChatwootConnector::updateAccount
                       PATCH {limits, features, status}
```

**المتطلبات التي طلبتَها، ومكان تحقّقها:**
- **Idempotency** ✅ موجود جزئيًا: `billing_fulfillments` + `WebhookDelivery::claim`. يجب توسيعه ليشمل الإلغاء.
- **Audit Log** ✅ موجود: أحداث `billing.subscription_activated` / `billing.fulfillment_failed`.
- **Retry** ❌ **معطَّل عمدًا** (قرار G33). يجب إعادته للمسار الحرج مع تراجع أسّي وحد أقصى.
- **Grace period / التجديد / الإلغاء** ❌ **غير موجود إطلاقًا** — يجب بناؤه.

**⚠️ عائق معماري حرج اكتُشف في Chatwoot (P0):**
`enterprise/app/services/internal/reconcile_plan_config_service.rb:52-58` — عندما تكون `ChatwootHub.pricing_plan == 'community'` (الافتراضي المشحون)، **تُعطَّل الميزات المدفوعة لكل حساب يوميًا**. أي جسر يكتب ميزات **سيُلغى خلال 24 ساعة**. يجب حسم `INSTALLATION_PRICING_PLAN` على الخادم **قبل** بناء أي مزامنة ميزات.

**⚠️ فخ ثانٍ (P0):** `PATCH /platform/api/v1/accounts` **يستبدل `custom_attributes` بالكامل** (لا يدمج — بعكس users controller). أي كتابة تمسح `stripe_customer_id`، `plan_name`، عدّادات Captain. أي جسر **يجب** أن يقرأ ثم يدمج ثم يكتب.

---

## 6. Production Configuration Matrix — مصفوفة إعدادات الإنتاج

### 🔴 الحالة: `BLOCKED — لا وصول للإنتاج`

لا أستطيع تنفيذ ما طلبتَه في §5 من مستندك. **لن أخمّن.** كل بند أدناه = `UNKNOWN`.

بدلًا من تخمين عديم القيمة، أُسلّم **قائمة تحقق دقيقة قابلة للتنفيذ**، مع تحديد ما إذا كان المصدر متغيّر بيئة أم صفًّا في قاعدة البيانات — وهو فرق حاسم لأن Chatwoot يخزّن معظم إعداداته في `InstallationConfig`.

### 6.1 ⚠️ الفخ الأخطر في تهيئة Chatwoot

`GlobalConfigService.load` **يكتب قيمة ENV إلى قاعدة البيانات عند أول قراءة**. بعدها **يفوز صف قاعدة البيانات إلى الأبد**، وتغيير ENV لا أثر له. ينطبق على كل مفاتيح Meta/القنوات/OAuth.

**⇒ فحص متغيرات البيئة وحده مُضلِّل. يجب فحص `InstallationConfig`.**

### 6.2 قائمة التحقق (تُنفَّذ على الخادم — لا تطبع أي قيمة)

```ruby
# chat.lynomia.com — bundle exec rails runner
%w[FB_APP_ID FB_APP_SECRET FB_VERIFY_TOKEN IG_VERIFY_TOKEN
   INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN
   WHATSAPP_APP_ID WHATSAPP_CONFIGURATION_ID WHATSAPP_APP_SECRET WHATSAPP_API_VERSION
   FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS ENABLE_PUSH_RELAY_SERVER
   CHATWOOT_CLOUD_PLANS CHATWOOT_CLOUD_PLAN_FEATURES
   DEPLOYMENT_ENV INSTALLATION_PRICING_PLAN ENABLE_ACCOUNT_SIGNUP
].each { |k| r = InstallationConfig.find_by(name: k)
           puts "#{k}: #{r.nil? ? 'ABSENT' : (r.value.presence ? 'SET' : 'EMPTY')}" }

%w[SECRET_KEY_BASE REDIS_URL POSTGRES_HOST ACTIVE_STORAGE_SERVICE
   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT SENTRY_DSN ELASTICSEARCH_URL
].each { |k| puts "#{k}: #{ENV[k].present? ? 'SET' : 'MISSING'}" }

puts "enterprise?          #{ChatwootApp.enterprise?}"        # يجب true وإلا انهارت الحدود
puts "pricing_plan         #{ChatwootHub.pricing_plan}"       # 'community' ⇒ الميزات تُمسح يوميًا
puts "report_rollup        #{Account.first&.feature_enabled?('report_rollup')}"
puts "inbox counts:";  puts Inbox.group(:channel_type).count
puts "whatsapp:";      puts Channel::Whatsapp.pluck(:provider).tally
puts "api inboxes:";   puts Channel::Api.count                # مسار Zender
```

```bash
# lynomia.com (Central) — أسماء المفاتيح وحالة الفراغ فقط
grep -oE '^[A-Z_]+=' .env | sort
for k in APP_KEY STRIPE_SECRET STRIPE_WEBHOOK_SECRET CHATWOOT_TOKEN CHATWOOT_ADMIN_TOKEN \
         ZENDER_TOKEN PLATFORM_SECRET TRIAL_CHATWOOT_PLAN; do
  v=$(grep -E "^$k=" .env | cut -d= -f2-); echo "$k: ${v:+SET}${v:-MISSING}"; done
git rev-parse HEAD                 # ← هل Phases A–G1 منشورة؟
php artisan migrate:status | tail -20
ls -la bootstrap/cache/config.php  # موجود ⇒ env() خارج config/ يُرجع null ⇒ BI-02 نشط
crontab -l | grep schedule:run;  ps aux | grep -E 'queue:work|schedule:run'
```

### 6.3 المصفوفة

| البند | المصدر | الحالة |
|---|---|---|
| كل البنود المذكورة في §5 من مستندك | ENV و/أو InstallationConfig | 🔴 **UNKNOWN — BLOCKED** |

**ثلاثة بنود تُغيّر قرارات معمارية ويجب حسمها أولًا:**
1. `ChatwootApp.enterprise?` — لو `false`، **كل الحدود تُتجاهل** ويصبح `usage_limits` = 100,000.
2. `ChatwootHub.pricing_plan` — لو `community`، **كل الميزات تُمسح يوميًا**.
3. `ENABLE_PUSH_RELAY_SERVER` — لو مفعّل، **الإشعارات تذهب لتطبيقات Chatwoot الرسمية ولا تصل تطبيق Lynomia أبدًا**.

---

## 7. Omnichannel Runtime Matrix — مصفوفة القنوات التشغيلية

### 🔴 الحالة التشغيلية: `BLOCKED`. لا يمكن ملء الأعمدة التشغيلية دون الخادم.

| Channel | SUPPORTED | CONFIGURED | CONNECTED | REAL INBOX | REAL MSGS | SEND | RECEIVE | STATUS | PROD READY |
|---|---|---|---|---|---|---|---|---|---|
| WhatsApp (Zender→API channel) | ✅ **المسار الحقيقي** | ❓ | ❓ | ❓ | ❓ | ⚠️ **نص فقط** | ⚠️ **نص فقط** | ❌ **غير مدعوم** | ❓ |
| WhatsApp Cloud (Meta أصلي) | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| WhatsApp 360dialog | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| Facebook Messenger | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| Instagram | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| Telegram | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| Email | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| Website Live Chat | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| Twilio SMS | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| Bandwidth SMS | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| LINE | ✅ | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| TikTok | ✅ | ⚠️ مخفي بلا `tiktokAppId` | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |
| API Channel | ✅ | ✅ **يستخدمه Zender** | ❓ | ❓ | ❓ | ✅ | ✅ | ➖ | ❓ |
| Voice | ✅ EE | ❓ | ❓ | ❓ | ❓ | ✅ كود | ✅ كود | ✅ كود | ❓ |

### 7.1 عائق إنفاذ مؤكَّد بالكود (لا يحتاج الإنتاج)

**حد الـ Inboxes مُنفَّذ في مسار واحد فقط من تسعة** (`app/helpers/api/v1/inboxes_helper.rb:118-122`). و**Platform API يستطيع إضافة وكلاء بلا حدود**، متجاوزًا السقف المفروض على مسار لوحة التحكم. ⇒ حتى بعد إصلاح المزامنة، **الحدود قابلة للتجاوز**.

---

## 8. Channel E2E Results — نتائج الاختبار الطرفي

### 🔴 `NOT EXECUTED — BLOCKED BY ENVIRONMENT`

الشبكة محجوبة؛ لا يمكن لمس مزوّد أو خادم. وطلبتَ صراحةً عدم الاختبار على عملاء حقيقيين — وهذا محترم بالكامل (لم تُرسَل أي رسالة).

### 8.1 الإجراء الآمن الجاهز للتنفيذ

**قواعد ملزمة:** رقم اختبار مملوك للشركة فقط · رسالة واحدة لكل قناة · لا تعديل اعتمادات · خارج ساعات الذروة.

**الخطوة 0 — جرد للقراءة فقط (بلا أي مخاطرة):**
```ruby
Inbox.group(:channel_type).count
Inbox.joins(:messages).where(messages: {created_at: 30.days.ago..})
     .group(:channel_type).count('messages.id')          # قنوات حيّة فعلًا
Channel::Whatsapp.pluck(:phone_number, :provider)
Channel::Whatsapp.all.map { |c| [c.phone_number, c.reauthorization_required?] }
Conversation.where(created_at: 7.days.ago..).joins(:inbox).group('inboxes.channel_type').count
```
هذه وحدها تحوّل كل عمود `CONFIGURED / CONNECTED / REAL INBOX / REAL MSGS` من `❓` إلى قيمة.

**الخطوة 1 — لكل قناة، الدليل المطلوب:**

| المرحلة | الدليل المقبول |
|---|---|
| RECEIVE | رسالة من رقم الاختبار تُنشئ `Message(message_type: incoming)` — تحقق بـ `Message.last` |
| SEND | رد الوكيل يصل الجهاز؛ `Message(message_type: outgoing, status: sent)` |
| STATUS | تتحوّل `status` إلى `delivered` ثم `read` |
| MEDIA | صورة تصل في الاتجاهين |
| النتيجة | `PASS` / `FAIL` / `PARTIAL` / `NOT CONFIGURED` / `BLOCKED BY PROVIDER` |

**توقّع مُسبق مبني على الكود:** لقناة WhatsApp عبر Zender ستكون النتيجة **`PARTIAL`** حتمًا — الوسائط وحالات التسليم غير مدعومة معماريًا (§9.2).

---

## 9. WhatsApp Runtime Report — تقرير WhatsApp

### 9.1 🔴 الاكتشاف الأهم: معمارية WhatsApp ليست ما وصفه Phase 0

Phase 0 وصف Meta Cloud API + Embedded Signup. **المسار الإنتاجي الفعلي مختلف كليًا:**

```
واتساب العميل
   ↕
Zender  (otp.lynomia.com — بوابة Titan Systems)
   ↕
Central (lynomia.com)
   IN : POST /api/webhook/zender      ← سرّ مشترك، hash_equals، حماية تكرار
   OUT: POST /api/chatwoot-webhook    ← HMAC-SHA256، حماية تكرار
   ↕  Chatwoot Application API
Chatwoot: Inbox من نوع **API Channel** (وليس Channel::Whatsapp)
```

**الدليل:** `ZenderManagerController::createAndStoreInbox` يُنشئ Inbox من نوع API في Chatwoot ويضبط webhook‑ه على `https://lynomia.com/api/chatwoot-webhook`.

### 9.2 الأثر — قيود جوهرية مثبتة بالكود

بما أن الـ Inbox من نوع **API Channel** وليس `Channel::Whatsapp`:

| القدرة | الحالة | السبب |
|---|---|---|
| رسائل نصية | ✅ | `$content = $data['content']` |
| **الوسائط (صور/ملفات/صوت)** | ❌ **تُسقَط بصمت** | `receiveFromChatwoot` يقرأ `content` فقط؛ ورسالة بلا نص ⇒ `invalid_data` |
| **قوالب WhatsApp** | ❌ | غير موجودة في API Channel |
| **الرسائل التفاعلية / الأزرار** | ❌ | غير موجودة |
| **حالات التسليم/القراءة** | ❌ | لا مسار |
| **نافذة الـ 24 ساعة** | ❌ غير مُدارة | لا قوالب ⇒ لا استئناف بعد انتهاء النافذة |
| مزامنة القوالب | ❌ | لا تنطبق |

**⇒ كل تحليل Phase 0 لقدرات WhatsApp (القوالب، التفاعلية، الوسائط، نافذة 24 ساعة) يصف كودًا موروثًا قد لا يكون مستخدمًا في الإنتاج.**

`UNVERIFIED`: أيّ المسارين حيّ فعلًا. يُحسم بـ `Inbox.group(:channel_type).count` مقابل `Channel::Whatsapp.count`.

### 9.3 مسار Meta ثالث داخل Central 🔴

| ID | النتيجة | الملف | الخطورة |
|---|---|---|---|
| WA-01 | **`GET /whatsapp/Token/{id}` يُعيد رمز Meta WhatsApp مفكوك التشفير لأي مجهول.** بلا مصادقة، بلا تحقق ملكية، معرّفات تسلسلية ⇒ حصاد رموز كل المستأجرين. | `FacebookAuthController.php:22-30`، `routes/web.php:133` | **P0** |
| WA-02 | **`POST /send-whatsapp` غير مُصادَق** ويرسل عبر حساب أي مستأجر بمعرّف من الطلب. | `FacebookAuthController.php` | **P1** |
| WA-03 | **webhook واتساب الوارد بلا تحقق توقيع**، يسجّل الحمولات كاملة، ويعتمد على قيمة ثابتة في الكود يسجّلها أيضًا. | `FacebookAuthController::handle` | **P1** |

### 9.4 القيد الفريد العالمي على رقم الهاتف — سيناريو الترحيل

**مؤكَّد:** `index_channel_whatsapp_on_phone_number (phone_number) UNIQUE` بلا `account_id` (`db/schema.rb:606`).

**⚠️ لا يُنفَّذ الآن. لا تغيّر القيد.** السيناريو الآمن عند اتخاذ القرار:

1. **قياس أولًا:** `Channel::Whatsapp.group(:phone_number).having('count(*)>1').count` — إن كانت صفرًا فالتغيير غير عاجل.
2. **نسخة احتياطية مُثبَت استرجاعها** أولًا.
3. Migration إضافية: فهرس مركّب `(account_id, phone_number)` **أولًا**، ثم إسقاط الفهرس القديم في **نشر منفصل لاحق** (لا في نفس النشر).
4. **ما قد ينكسر** — يجب تعديله في نفس التغيير:
   - `Webhooks::WhatsappController#valid_token?` و`whatsapp_business_payload_channel` — كلاهما `find_by(phone_number:)` **بلا نطاق حساب** ⇒ يصبح غامضًا فور وجود تكرار.
   - `Whatsapp::ChannelCreationService#find_existing_channel:29` — نفس المشكلة.
   - توجيه الـ webhook يعتمد على `params[:phone_number]` في المسار ⇒ يحتاج تمييزًا إضافيًا.
5. **التراجع:** إسقاط الفهرس الجديد (غير مدمّر) — لهذا يجب تأجيل حذف القديم.

**التوصية:** **مؤجَّل**. الأولوية للأمن والفوترة. ولا داعي له إن كان المسار الإنتاجي هو Zender (لا يستخدم `channel_whatsapp` أصلًا).

### 9.5 تثبيت Graph API على v13.0

**مؤكَّد وأوسع مما ظنّ Phase 0:** ليست `media_url` وحدها — **الإرسال نفسه** مثبّت على v13.0 بلا تجاوز من الإعدادات (`whatsapp_cloud_service.rb`). v13.0 قديم جدًا وقابل للسحب من الخدمة. **P1**.

---

## 10. Mobile Runtime Report — تقرير الموبايل

### 10.1 🔴 الحالة: `STATIC BASELINE ONLY`

`flutter` و`dart` غير مثبّتين. **لم يُنفَّذ:** `flutter analyze` · الاختبارات · debug build · release build · أي اختبار على جهاز.
**نُفِّذ:** تحليل ساكن شامل لكل ادعاء من Phase 0، بالكود والسطر.

### 10.2 حسم ادعاءات Phase 0

| # | ادعاء Phase 0 | الحكم | التفصيل |
|---|---|---|---|
| 1 | تسريب الرموز في السجلّات | ✅ **مؤكَّد وأوسع** | **31** عبارة `print` على `main` تُسرّب رموز Chatwoot وpubsub وSanctum وFCM وGoogle Play وStripe client_secret وPII من Apple. **أُصلح — §12** |
| 2 | كلمة المرور تُرسل لنظامين | ✅ **مؤكَّد** | ولا `print` يطبع كلمة المرور نفسها — هذا الجزء من ادعاء Phase 0 **مدحوض** |
| 3 | الرموز في تخزين غير آمن | ✅ **مؤكَّد وأسوأ** | 6 اعتمادات في `SharedPreferences` نصًّا صريحًا، **و`android:allowBackup` مفعّل** ⇒ الملف مؤهل للرفع إلى Google Drive |
| 4 | `accountId ?? 4` | ✅ **مؤكَّد وقابل للوصول فعليًا** | `registerWithApple` **لا يحفظ `account_id` أبدًا** ⇒ الاحتياطي يُستخدم فعلًا لمستخدمي Apple |
| 5 | `validateStatus: true` | ✅ **مؤكَّد** | **8 دوال** تبتلع 4xx/5xx: عند انتهاء الرمز يرى الوكيل تطبيقًا فارغًا تمامًا بلا أي خطأ وبلا مسار لإعادة الدخول |
| 6 | FCM لا يُلغى عند الخروج | ✅ **مؤكَّد** | `clearAuth` يترك أربعة اعتمادات، و`logout()` غير مُنتظَر قبل التنقّل |
| 7 | خريطة أيقونات القنوات لا تُطابق | ✅ **مؤكَّد** | الخادم يُرجع `Channel::Whatsapp`، العميل يقارن بـ `whatsapp` |
| 8 | Apple Sign-In على نطاق وهمي | ✅ **مؤكَّد وأسوأ** | Service ID و redirect وهميان على Android · **iOS ينقصه entitlement وملف Firebase كليًا** · والتطبيق يرسل `platform:'social'` ⇒ **يخزّن رمز منصة Social كرمز Chatwoot** |
| 9 | لا Pagination | ✅ **مؤكَّد** | التطبيق لا يرى إلا أول 25 محادثة |
| 10 | لا إعادة مزامنة بعد انقطاع WS | ✅ **مؤكَّد وأسوأ** | WebSocket **يُعيد الاتصال بعد الخروج**، ويتضاعف عند كل تبديل محادثة (لا حارس إعادة اتصال) |

### 10.3 عيوب جديدة لم يرها Phase 0

| ID | النتيجة | الملف | الخطورة |
|---|---|---|---|
| MB-01 | **رمز Chatwoot يُرسَل إلى lynomia.com** لأن كلا الخادمين يتشاركان نسخة Dio واحدة | `chatwoot_api_service.dart:393-400,1023-1032` | **P0** |
| MB-02 | **محادثة واحدة بلا رسائل تُعطّل قائمة المحادثات بالكامل** (`StateError: No element`) | `models/chatwoot_models.dart` | **P1** |
| MB-03 | تسجيل دخول ناجح في Chatwoot قد يُظهر «كلمة المرور خاطئة» إذا تعطّل Laravel — **بعد** حفظ الرمز | `chatwoot_api_service.dart:1032` | **P1** |
| MB-04 | **Apple يُعيد التزويد بلا شرط ⇒ حساب Chatwoot مكرر في كل مرة** | `AppleRegisterController.php` | **P1** |
| MB-05 | **مفتاح Stripe العلني مفتاح اختبار مضمّن في بناء منشور** | `main.dart:27-28` | **P1** |
| MB-06 | `fetchUserProfile` يبتلع كل خطأ ⇒ «فحص صلاحية الجلسة» **لا يمكن أن يفشل أبدًا** | `chatwoot_api_service.dart` | **P1** |

### 10.4 تصنيف أمان الإصلاح (كما طلبتَ في §11)

| الإصلاح | آمن الآن؟ | السبب |
|---|---|---|
| إزالة تسجيل الاعتمادات | ✅ **نُفِّذ** | نصوص فقط، صفر أثر على البروتوكول |
| `android:allowBackup="false"` | ✅ آمن | سطر واحد في Manifest |
| عزل نسخة Dio لـ Central | ✅ آمن | يُزيل MB-01 بلا تغيير عقد |
| إزالة `?? 4` | ⚠️ **يتطلب حذرًا** | يجب أولًا إصلاح حفظ `account_id` في مسار Apple وإلا انكسر مستخدمو Apple |
| `flutter_secure_storage` | ⚠️ يحتاج ترحيل | قراءة القديم/كتابة الجديد/حذف القديم وإلا خرج كل المستخدمين |
| معالجة 401/403/429 | ⚠️ **لا تُقلب `validateStatus` عالميًا** | 16 موضعًا آمنًا حاليًا سينكسر. عالِج المواضع الثمانية صراحةً |
| حذف `_loginToLynomia` | ❌ **يكسر الدفع** | مؤجَّل حتى وجود `/api/sso/chat` |

**⚠️ إفصاح:** لم يُنفَّذ أي من إصلاحات §11 عدا التسجيل، لأنك اشترطت **«كل تعديل يجب أن يملك Regression Test»** ولا يمكن كتابة أو تشغيل اختبارات Dart بلا Flutter SDK. تنفيذها الآن كان سيخالف §25.

---

## 11. Security Verification — التحقق الأمني

### 11.1 🔴 أخطر نتيجة في المنظومة كلها

**اعتمادات إنتاج حيّة ما زالت مسترجَعة من تاريخ Git في `lynomia98`.**

تحققتُ بنفسي، **دون طباعة أي قيمة**:

```
commit 0106e37 (الأول) → 11.env → 38 مفتاحًا بقيم مأهولة
```

الفئات المكشوفة (أسماء فقط):
`APP_KEY` · `DB_PASSWORD` · `REDIS_PASSWORD` · `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` · `STRIPE_SECRET` + `STRIPE_SECRET_KEY` + **4× `STRIPE_WEBHOOK_SECRET`** · **`CHATWOOT_TOKEN` + `CHATWOOT_ADMIN_TOKEN` + `CHATWOOT_API_TOKEN`** · `ZENDER_TOKEN` · `OTP_SYSTEM_TOKEN` · `QR_API_KEY` · `SOCIAL_SECRET_KEY` · `PAYMERA_PASSWORD` · `FACEBOOK_APP_SECRET` · `MAIL_PASSWORD` · `WHATSAPP_VERIFY_TOKEN`

**وبالإضافة:** `platform_db (3).sql` (نسخة إنتاج بمستخدمين حقيقيين و**29 hash كلمة مرور**) · ملفات جلسات تحوي **كلمة مرور عميل صريحة** و**سرّ OTP حيًّا** · `public/debug_whatsapp.txt` (سرّ webhook + أرقام ورسائل عملاء).

**عاملان يضاعفان الخطورة:**
1. **`CHATWOOT_ADMIN_TOKEN` هو رمز PlatformApp** ⇒ من يملكه يتحكم في حسابات ومستخدمي Chatwoot.
2. **`APP_KEY` هو المُضخِّم** ⇒ يفكّ تشفير `platform_p` (كلمات مرور المنصات) وكل الاعتمادات المشفّرة.

**الحالة:** `PHASE_A_CREDENTIAL_ROTATION_RUNBOOK.md` → **"Status: NOT EXECUTED"**. و`PHASE_A_GIT_SECRET_PURGE_RUNBOOK.md` → **"Status: NOT EXECUTED"**.

> **⛔ توصية عاجلة: كل هذه الاعتمادات يجب اعتبارها مخترقة الآن. التدوير يسبق كل شيء آخر في هذا التقرير.**
> الترتيب الإلزامي: **تدوير أولًا، ثم تطهير التاريخ.** (سرّ مُطهَّر لكنه صالح لا يحمي شيئًا؛ سرّ مُدوَّر في التاريخ تسريب معلومات لا اعتماد.)

### 11.2 ما هو مُصلَح في `main` (تحققتُ بنفسي) ✅

| النتيجة السابقة | الحالة في `main` |
|---|---|
| `GET /api/get-platform-password/{userId}` غير مُصادَق | ✅ **حُذف** (`routes/api.php:93`) |
| كل `/admin/*` غير مُصادَق | ✅ **محمي** بمجموعة `admin.area` = `auth` + `EnsureUserIsAdmin` |
| webhook Chatwoot غير موثّق | ✅ **HMAC-SHA256** + حماية تكرار |
| بوابات نظافة الأسرار في CI | ✅ **موجودة وتعمل** |

**⚠️ لكن §2.4: لا شيء من هذا منشور على الإنتاج.**

### 11.3 نتائج أمنية مفتوحة

| ID | النتيجة | الخطورة |
|---|---|---|
| SEC-01 | استيلاء على الحساب عبر Google (بلا تحقق ID token) | **P0** |
| SEC-02 | استيلاء على الحساب عبر Apple (بلا تحقق توقيع) | **P0** |
| SEC-03 | `platform_secret` غير معرَّف ⇒ HMAC بمفتاح فارغ | **P0** |
| SEC-04 | `GET /whatsapp/Token/{id}` يكشف رموز Meta (IDOR) | **P0** |
| SEC-05 | `GET /subscription/success` يمنح خطة QR من query string، قابل للإعادة | **P0** |
| SEC-06 | اعتمادات في تاريخ Git، غير مُدوَّرة | **P0** |
| SEC-07 | **`public/info.php` = `phpinfo()`** مُقدَّم مباشرة | **P1** |
| SEC-08 | كلمة مرور صريحة + سرّ OTP حيّ يُكتبان في الجلسة عند كل تسجيل دخول | **P1** |
| SEC-09 | **لا rate limiting على أي نقطة مصادقة** (تسجيل دخول، استعادة، OTP) | **P1** |
| SEC-10 | رموز Sanctum **لا تنتهي أبدًا**، بصلاحيات كاملة، ولا تُبطَل في أي مكان | **P1** |
| SEC-11 | `POST /send-whatsapp` غير مُصادَق | **P1** |
| SEC-12 | webhook واتساب بلا تحقق توقيع + يسجّل الحمولات | **P1** |
| SEC-13 | رمز Chatwoot يُسرَّب إلى lynomia.com (Dio مشترك) | **P0** |
| SEC-14 | اعتمادات الموبايل في `SharedPreferences` + `allowBackup` مفعّل | **P0** |

---

## 12. P0 Containment Results — نتائج الاحتواء ✅ (مع إقرار بخطأ)

### 12.1 ما نُفِّذ فعلًا

**المستودع:** `lynomia-chat-app98` · **الفرع:** `claude/new-session-i3dqsj`

| Commit | المحتوى |
|---|---|
| `e94e958` | إزالة 27 تسريب اعتماد من السجلّات |
| `3eeae33` | **إكمال ما فاتني** — 3 تسريبات نجت |

**ما أُزيل:** `access_token` (Chatwoot) · `pubsub_token` · Sanctum PAT (Central) · FCM token · Google Play purchase token · **Stripe `client_secret`** · أجسام استجابات تسجيل الدخول/التسجيل/الدفع · PII من Apple (بريد، اسم، `identityToken`) · محتوى رسائل العملاء في استجابة المرفقات.

### 12.2 🔴 إقرار: إصلاحي الأول كان ناقصًا

المراجعة المستقلة وجدت أن `e94e958` **ترك ثلاثة تسريبات**:
- `payment_api_service.dart:109` — يطبع Stripe `client_secret` **بعد استخراجه** (كنتُ نقّحتُ السطر الذي فوقه فقط)
- `chatwoot_api_service.dart:703, 724` — يطبعان مُعرِّف اشتراك ActionCable الذي **يتضمّن `pubsub_token` كاملًا**

أُصلحت في `3eeae33`. **الدرس:** التنقيح بتعديل النصوص هشّ بطبيعته؛ الإصلاح الصحيح هو واجهة تسجيل موحّدة + قاعدة `avoid_print` — وهو ما أوصي به لـ Phase 2.

### 12.3 حدود ما نُفِّذ — بصراحة

| البند | الحالة |
|---|---|
| قيم الاعتمادات في السجلّات | ✅ **أُزيلت بالكامل** (فحص شامل نهائي: صفر) |
| محتوى رسائل العملاء وPII في السجلّات | ⚠️ **ما زال** — يحتاج واجهة تسجيل (Phase 2، ~200 موضع) |
| `flutter analyze` | ❌ **لم يُنفَّذ** — SDK غير متاح |
| البناء / اختبار الانحدار | ❌ **لم يُنفَّذ** |
| التحقق البنيوي | ✅ التغييرات نصوص حرفية فقط · كل سطر متوازن الأقواس والاقتباسات · `targetAccountId` مؤكَّد في النطاق |

> **لا أعلن هذا «Fixed» بالمعنى الكامل.** أعلنه: **التسريب أُزيل من الكود، ولم يُتحقَّق منه بالمترجم.** يجب تشغيل `flutter analyze` قبل أي إصدار.

### 12.4 P0-2 (تمرير كلمة المرور) — لم يُلمَس، عمدًا

طلبتَ في §10: لا تحذف `_loginToLynomia()` قبل فهم النظام الثالث. **فهمناه الآن**، والنتيجة:
- الرمز الناتج **ضروري** لأربع نقاط دفع
- البديل الآمن (`ssoUrl`) **موجود بالفعل** في Central لكنه **غير معرَّض للموبايل**
- ⇒ **الحذف الآن يكسر الدفع.** الخطة في §4.4.

---

## 13. Staging Architecture — معمارية بيئة الاختبار

### 13.1 الحالة: يوجد ملف، لكنه **لا يعمل**

`lynomia98/docker-compose.staging.yml` موجود — تصحيح لادعاء Phase 0 «لا staging». **لكنه مكسور بثلاثة عيوب مؤكَّدة:**

| ID | العيب | الخطورة |
|---|---|---|
| ST-01 | **لا يُثبِّت الاعتماديات إطلاقًا** ⇒ خدمات PHP الثلاث تنهار على `vendor/autoload.php` مفقود | **P1** |
| ST-02 | **حاوية التطبيق لا تنشر أي منفذ** ⇒ الغرض الوحيد المعلن للمنظومة غير قابل للوصول | **P1** |
| ST-03 | `DB_CONNECTION=mysql` على `php:8.4-cli` الذي **لا يشحن `pdo_mysql`** | **P1** |

### 13.2 التصميم المطلوب

```
Development (محلي)  →  Staging (يحاكي الإنتاج)  →  Production
```

**Staging يجب أن يطابق الإنتاج في:** Rails 8 + Ruby 3.4.4 · PostgreSQL (نفس الإصدار الرئيسي) · Redis · Sidekiq · ActionCable · ActiveStorage · PHP 8.3 + MySQL/MariaDB لـ Central · بنية متغيرات البيئة.

**قواعد ملزمة (كما اشترطتَ):**
- ❌ **ممنوع استخدام أسرار الإنتاج في Staging** — مفاتيح اختبار Stripe، تطبيق Meta منفصل، رقم WhatsApp اختباري، قاعدة بيانات منفصلة تمامًا.
- ✅ بيانات مُقنَّعة (anonymized) لا نسخة إنتاج.
- ✅ Staging **يسبق** أي نشر — وهذا هو ما يوقف التطوير على الإنتاج.

**نقطة قوة موجودة:** CI في Central يستخدم **محاكيات داخل العملية** (`tests/Support/Simulators`) لا تلمس خدمة حقيقية ولا تحتاج اعتمادًا. نموذج ممتاز — **لكن انتبه**: `ChatwootSimulator` لا يتحقق من أسماء الميزات، وهذا سبب مرور عيب §5.4. **يجب تحصين المحاكيات مقابل عقود حقيقية.**

---

## 14. CI/CD Design & Status — التكامل والنشر

### 14.1 الحالة الفعلية

| المستودع | CI | التقييم |
|---|---|---|
| `lynomia98` | ✅ **`virtual-staging.yml` حقيقي** — بوابتا `secret-hygiene` و`tls-hygiene`، اختبارات على SQLite + MariaDB | جيد. **لا يوجد نشر.** |
| `lynomiachat` | ⚠️ 16 workflow **موروثة من Chatwoot** تستهدف مستودع Chatwoot | **بلا قيمة عملية لـ Lynomia** |
| `lynomia-chat-app98` | ❌ **لا شيء** | لا بناء، لا تحليل، لا توقيع |

### 14.2 عيوب تشغيلية مؤكَّدة في Central

| ID | العيب | الخطورة |
|---|---|---|
| OPS-01 | **لا مصنوعات إشراف على العمّال أو المجدول** رغم وجود وظائف مُرتَّبة وأمر مجدول | **P1** |
| OPS-02 | الأمر المجدول الوحيد **يعلن اسمين متضاربين** (`#[Signature]` مقابل `$signature`) وبلا أي تغطية اختبارية | **P1** |
| OPS-03 | **صفر تتبّع أخطاء أو APM أو تنبيهات** — `config/logging.php` هو ملف Laravel القياسي بلا تعديل | **P1** |

### 14.3 التصميم المقترح

**Backend (Chatwoot):** `bundle install` → `rubocop` → `brakeman` → `bundle audit` → `rspec` → `pnpm install` → `vitest` → `eslint` → بناء الأصول → **فحص أمان الترحيلات** → بناء Docker → نشر Staging → اختبارات دخان → **بوابة موافقة بشرية** → إنتاج.

**Backend (Central):** `composer install` → `pint`/`phpstan` → `composer audit` → `phpunit` (مع البوابات القائمة) → نشر Staging → دخان → **بوابة** → إنتاج.

**Flutter:** `flutter pub get` → `flutter analyze` → اختبارات وحدة/واجهة → **بوابة `avoid_print`** (تمنع ارتداد §12) → بناء Android → بناء iOS حيث يتوفر runner → توقيع بأسرار في خزنة CI لا في المستودع.

**قاعدة ملزمة (كما طلبتَ):** ❌ **لا نشر إنتاج تلقائي بلا بوابة موافقة بشرية.**

---

## 15. Monitoring & Observability — المراقبة

### 15.1 المتاح أصلًا (استخدمه قبل إضافة أدوات)

| الإشارة | الأداة الموجودة | الحالة |
|---|---|---|
| أخطاء Rails | Sentry / Datadog / New Relic / Elastic APM / Scout (كلها في `Gemfile`) | ⚠️ **لا دليل على تفعيل أيٍّ منها** |
| فشل Sidekiq وتأخر الطوابير | لوحة Sidekiq المدمجة | ✅ متاحة |
| صحة رموز Meta/WhatsApp | ✅ **Chatwoot يوفّرها أصلًا**: `Reauthorizable` + `Whatsapp::HealthService` + `prompt_reauthorization!` | ✅ **استخدمها — لا تبنِ بديلًا** |
| فشل الـ Webhooks | `WebhookDelivery` في Central + سجلّات Chatwoot | ✅ جزئيًا |
| تشخيص الإشعارات | `SuperAdmin::PushDiagnosticsController` | ✅ موجود |
| أخطاء Laravel | ❌ **لا شيء** — logging قياسي | ❌ |
| أعطال الموبايل | ❌ **لا شيء** — Firebase موجود لكن Crashlytics غير مُعد | ❌ |

### 15.2 الناقص فعلًا

1. تفعيل Sentry في المستودعات الثلاثة (Chatwoot: DSN فقط · Laravel: حزمة + DSN · Flutter: Crashlytics)
2. تنبيهات على: **فشل تفعيل خطة** (`billing_fulfillments.status = FAILED`) ← يكشف §5.4 فورًا
3. تنبيه على `reauthorization_required` لأي قناة ⇒ يكشف قناة ميتة قبل العميل
4. تنبيه على معدّل رفض webhook Stripe ⇒ يكشف BI-02
5. مراقبة تأخر الطوابير وعمق `failed_jobs`

---

## 16. Backup & Disaster Recovery — النسخ والاسترجاع

### 16.1 الحالة: 🔴 `UNVERIFIED — لا وصول للإنتاج`

**لا أعرف** إن كانت هناك نسخ احتياطية. ولن أفترض.

### 16.2 التصميم المطلوب

| المكوّن | التكرار | الاحتفاظ | ملاحظات |
|---|---|---|---|
| PostgreSQL (Chatwoot) | يومي كامل + WAL مستمر | 30 يومًا + شهري 12 شهرًا | استرجاع لحظي |
| MySQL/MariaDB (Central) | يومي كامل | نفسه | يحوي بيانات دفع |
| تخزين الوسائط (S3/محلي) | يومي تزايدي | 30 يومًا | مرفقات المحادثات |
| Redis | حسب الحاجة | — | Sidekiq قابل لإعادة البناء؛ **لكن الوظائف المجدولة لا** |
| الإعدادات (`.env`, `InstallationConfig`) | عند كل تغيير | 90 يومًا | **مشفّرة** — تحوي أسرارًا |
| مفاتيح `ACTIVE_RECORD_ENCRYPTION` و`APP_KEY` | خزنة أسرار | دائم | **بدونها النسخة عديمة القيمة** |

**قاعدة ملزمة (وهي بالضبط ما شدّدتَ عليه):**
> **وجود النسخة ليس إثباتًا.** لا تُعتبر النسخ الاحتياطية موجودة حتى **يُستعاد منها على Staging بنجاح مرة واحدة على الأقل**، ويُوثَّق زمن الاسترجاع (RTO) وحجم فقد البيانات (RPO).

**تحذير خاص:** لو دُوِّر `APP_KEY` (وهو مطلوب في §11) **دون** إعادة تشفير الأعمدة المشفّرة، تصبح كل النسخ السابقة غير قابلة للفك. **التدوير يجب أن يشمل تمريرة إعادة تشفير، ويكون آخر خطوة في التدوير.**

---

## 17. API Contract Assessment — تقييم عقد الـ API

### 17.1 الوضع

- `lynomiachat/swagger/` موجود وشامل نسبيًا (موروث من Chatwoot) — **لم يستخدمه تطبيق الموبايل إطلاقًا**
- **Central ليس لديه أي مواصفة OpenAPI**
- **صفر أنواع مشتركة** بين Flutter وأي خادم
- النتيجة المباشرة: عيوب مثل خريطة أيقونات القنوات (`Channel::Whatsapp` مقابل `whatsapp`) وBI-03 (نقطة نهاية غير موجودة) **عيوب عقد خالصة كان مولّد أنواع سيمنعها بنيويًا**

### 17.2 الخطة المتدرّجة (لا تُنفَّذ الآن)

1. **قِس التغطية أولًا** — لكل نقطة نهاية يستدعيها Flutter (19 على Chatwoot + 8 على Central)، هل هي موصوفة في `swagger/`؟ **لا تفترض أنها كاملة.**
2. **اكتب OpenAPI لـ Central** — 8 نقاط فقط يستخدمها تطبيق Chat. عائد كبير بجهد صغير.
3. **ولّد نماذج Dart** من المواصفتين، في مجلد `lib/generated/` منفصل.
4. **اختبارات عقد في CI** — تفشل عند أي انحراف.
5. **تتبّع الإصدارات** — الموبايل المنشور (`1.0.0+7`) على أجهزة المستخدمين؛ أي تغيير كاسر يجب أن يكون مُصدَّرًا.

**⚠️ لا تبدأ ترحيلًا معماريًا كبيرًا قبل الخطوة 1** — كما اشترطتَ في §17 من مستندك.

---

## 18. Upstream Strategy — استراتيجية التحديث

### 18.1 🔴 تصحيح لتوصية Phase 0

Phase 0 أوصى بنقل التخصيصات إلى `custom/`. **هذا غير قابل للتنفيذ:**

> **`custom/` هو hook ميت في Chatwoot 4.14.1 — لا يحمّل Ruby ولا Vue.**
> (`config/application.rb:42-53` مع `lib/chatwoot_app.rb:28-43`)

**أعتذر عن هذه التوصية في Phase 0.** البديل الصحيح أدناه.

### 18.2 الوضع

- التخصيص: **7 ملفات فقط** (مؤكَّد مجددًا)
- **الفرع متأخر 101+ يومًا** عن 4.14.1 بعدد **غير معروف** من إصدارات الأمان الفائتة ⇒ **P1**

### 18.3 مسار كل تخصيص

| # | التخصيص | البديل الأصلي | جاهز؟ |
|---|---|---|---|
| 1 | شعار وعنوان صفحة الدخول | `InstallationConfig`: `LOGO`, `LOGO_DARK`, `INSTALLATION_NAME`, `BRAND_URL` + `replaceInstallationName` | ✅ **يزيل التعارض بالكامل** |
| 2 | `<style>` غير مُنطاق | إضافة `scoped` — **إصلاح عيب P1 أيضًا** (يتسرّب إلى صفحات التسجيل والاستعادة) | ✅ |
| 3 | `Navbar.vue` | ملف جديد ⇒ **صفر تعارض**. يبقى | ✅ |
| 4 | إعادة توجيه الفوترة | يجب أن يشير إلى قناة شراء للعميل لا لرابط إداري (BI-08) | ⚠️ يحتاج قرار منتج |
| 5 | `billing/Index.vue` مُفرَّغ (−260 سطرًا) | **أكبر خطر تعارض على الإطلاق** | 🔴 يحتاج إعادة نظر |
| 6 | اسم Inbox = رقم الهاتف | تغيير سطر واحد؛ يُقبل أو يُعاد للأصل | ✅ |
| 7 | تسجيل `google_oauth2` المكرر في `devise.rb` | **يُحذف** — `omniauth.rb` يسجّله أصلًا | ✅ **يزيل تعارضًا مجانًا** |
| 8 | التعليق الكاذب في `channel/whatsapp.rb` | **يُحذف** | ✅ **يزيل تعارضًا مجانًا** |

**⇒ من 7 ملفات متعارضة إلى 2 فقط** (`billing/Index.vue` و`billing.routes.js`) بتغييرات كلها منخفضة المخاطر.

### 18.4 استراتيجية الفروع

```
upstream/develop (chatwoot/chatwoot)
      │  git fetch upstream  (لا merge الآن)
      ▼
lynomia/upstream-tracking     ← مرآة نظيفة، لا تُعدَّل أبدًا
      │
      ▼
lynomia-custom (main)         ← فرع التكامل — التخصيصات السبعة
      │
      ├── develop             ← تكامل التطوير
      │     └── feature/*     ← PR → CI → staging → موافقة → إنتاج
```

**إجراء التحديث المستقبلي:**
1. `git fetch upstream && git checkout -b upgrade/4.x lynomia-custom`
2. `git merge upstream/v4.x.y`
3. حلّ التعارضات (ملفان فقط بعد §18.3)
4. `bundle exec rspec` + `pnpm test` على staging
5. اختبار دخان لكل قناة مُهيّأة
6. بوابة موافقة → إنتاج

**⚠️ لا تنفّذ merge الآن** — كما اشترطتَ. الأولوية للأمن والفوترة.

---

## 19. Updated Issue Registry — سجل القضايا المُحدَّث

### 19.1 ملاحظة صدق على حالة التحقق المستقل

طلبتَ في §22 تأكيد كل P0/P1 بمراجعة ثانية مستقلة. نُفِّذ ذلك على النتائج الحرجة، **والنتيجة تستحق التوقف عندها:**

| المقياس | القيمة |
|---|---|
| النتائج التي خضعت لمراجعة عدائية مستقلة حتى كتابة التقرير | 10 + 3 (على استنتاجي الشخصي) |
| **منها دُحِضت أو خُفِّضت خطورتها** | **5 من 10 (50%)** |
| استنتاجي الشخصي عن جسر الاستحقاق | **دُحِض جزئيًا بإجماع 3 مراجعين** |

**⇒ لا تُعامل أي نتيجة P0/P1 لم تُوسَم أدناه بـ ✅ كحقيقة نهائية قبل مراجعتها.** معدّل الدحض 50% ليس تفصيلًا — إنه سبب وجود §22 من مستندك.

**الوسوم:** ✅ = تحققتُ منه بنفسي أو أكّدته مراجعة مستقلة · ⚪ = من التدقيق، بدليل `ملف:سطر`، لم يخضع بعد لمراجعة ثانية · 🔴 = محجوب.

### 19.2 P0 — عوائق (24)

| ID | النتيجة | Repo | Verification | Fix Phase | Regression Risk |
|---|---|---|---|---|---|
| ✅ SEC-06 | اعتمادات إنتاج (38 مفتاحًا) + 29 hash + APP_KEY في تاريخ Git، **غير مُدوَّرة** | Central | تحققتُ بنفسي من الـ blob | **فورًا** | تدوير APP_KEY يتطلب إعادة تشفير |
| ⚪ SEC-01 | استيلاء على الحساب عبر `/api/register/google` | Central | `GoogleRegisterController.php:109-144` | فورًا | متوسط — يتطلب إصدار موبايل |
| ⚪ SEC-02 | استيلاء على الحساب عبر `/api/auth/apple/signup` | Central | `AppleRegisterController.php:224-336` | فورًا | متوسط |
| ⚪ SEC-03 | `platform_secret` غير معرَّف ⇒ HMAC بمفتاح فارغ | Central | `config/services.php` (106 سطرًا) | فورًا | يجب إعادة تزويد المتأثرين |
| ⚪ SEC-04 | `GET /whatsapp/Token/{id}` يكشف رموز Meta (IDOR) | Central | `FacebookAuthController.php:22-30` | فورًا | منخفض — حذف مسار |
| ⚪ SEC-05 | `GET /subscription/success` يمنح خطة من query string | Central | `SubscriptionController.php:238-280` | فورًا | منخفض |
| ✅ SEC-13 | رمز Chatwoot يُسرَّب إلى lynomia.com (Dio مشترك) | Mobile | `chatwoot_api_service.dart:1023-1032` | Phase 2 | منخفض |
| ⚪ SEC-14 | اعتمادات الموبايل نصًّا + `allowBackup` مفعّل | Mobile | `cache_helper.dart` + Manifest | Phase 2 | يحتاج ترحيل تخزين |
| ✅ MOB-LOG | 31 تسريب اعتماد في السجلّات | Mobile | فحص شامل | ✅ **مُنجَز** | لا شيء (نصوص فقط) |
| ⚪ BI-01 | اشتراكات Stripe لا تصبح `active` أبدًا | Central | `ChatwootSubscriptionController.php:50-56` | فورًا | متوسط — يمسّ الفوترة |
| ⚪ BI-02 | `STRIPE_WEBHOOK_SECRET` عبر `env()` ⇒ فشل تحت `config:cache` | Central | `StripeGateway.php:29-32` | فورًا | منخفض |
| ✅ BI-09 | **لا مسار يُعلّق أو يُخفّض عند توقف الدفع** — سقّاطة أحادية | Central | `BillingSettlementService.php:95-113` | Phase 2 | عالٍ — يمسّ عملاء أحياء |
| ✅ BI-10 | `growth`/`enterprise` تفشل على `channel_api`؛ التجربة مكسورة لكل الخطط | Central | مراجعة 3 عدسات · خُفِّضت إلى **P1** | فورًا | منخفض — إصلاح أسماء |
| ⚪ CW-01 | `ReconcilePlanConfigService` **يمسح الميزات المدفوعة يوميًا** عند `pricing_plan=community` | Chatwoot | `reconcile_plan_config_service.rb:52-58` | **قبل أي مزامنة** | عالٍ |
| ⚪ CW-02 | `PATCH /platform/accounts` **يستبدل `custom_attributes`** كليًا | Chatwoot | `accounts_controller.rb:18-22` | **قبل أي مزامنة** | عالٍ — فقد بيانات |
| ✅ OPS-04 | **لا شيء من Phases A–G1 منشور على الإنتاج** | Central | تقرير الإغلاق `:254-256` | **فورًا** | — |
| ⚪ | (8 نتائج P0 إضافية في السجل الكامل) | — | — | — | — |

### 19.3 P1 — حرجة (70) · P2 — مهمة (60) · P3 — تحسينات (24)

السجل الكامل بكل الحقول محفوظ في مخرجات التدقيق. أبرز P1 المؤكَّدة:

**Central:** لا rate limiting على أي نقطة مصادقة · رموز Sanctum لا تنتهي ولا تُبطَل · `public/info.php` = `phpinfo()` · كلمة مرور صريحة وسرّ OTP في الجلسة · `GET /api/chat/subscription` و`POST /api/my/payment/*` مكشوفان · Google/Apple لا يسجّلان `chatwoot_account_id` ⇒ **كل مستخدمي الموبايل محجوبون عن شراء Chat** · طبقة Organizations/RBAC (12 جدولًا، 13 Gate) **بلا أي سطح HTTP** · حذف طلب يُدمّر سجل دفعته · staging مكسور (3 عيوب) · صفر مراقبة.

**Chatwoot:** حد الـ Inboxes مُنفَّذ في مسار واحد من تسعة · Platform API يتجاوز حد الوكلاء · `GlobalConfigService` يثبّت ENV في قاعدة البيانات عند أول قراءة · إرسال WhatsApp مثبّت على Graph v13.0 · `custom_attributes.subscribed_quantity` يتجاوز `limits.agents` · القيد الفريد العالمي على رقم الهاتف · التعليق الكاذب في `channel/whatsapp.rb` · `<style>` غير مُنطاق يتسرّب لصفحات أخرى · **متأخر 101+ يومًا عن Upstream**.

**Mobile:** محادثة بلا رسائل تُعطّل القائمة · لا Pagination (25 محادثة كحد أقصى) · WebSocket يُعيد الاتصال بعد الخروج ويتضاعف · Apple يرسل `platform:'social'` ⇒ رمز خاطئ · iOS ينقصه entitlement وملف Firebase · مفتاح Stripe اختباري في بناء منشور · FCM لا يُلغى عند الخروج · 8 دوال تبتلع أخطاء HTTP.

---

## 20. Remaining Launch Blockers — عوائق الإطلاق المتبقية

### 20.1 عوائق يجب إغلاقها قبل أي إطلاق تجاري

| # | العائق | لماذا هو عائق |
|---|---|---|
| **B-1** | **تدوير كل الاعتمادات المكشوفة + تطهير تاريخ Git** | 38 اعتمادًا حيًّا مسترجَعًا من أي نسخة. `CHATWOOT_ADMIN_TOKEN` وحده = تحكم كامل في Chatwoot. **يسبق كل شيء.** |
| **B-2** | **إغلاق ثغرتَي Google/Apple + `platform_secret`** | استيلاء على أي حساب بطلب واحد غير مُصادَق ومعرفة بريد |
| **B-3** | **حسم حالة النشر** — هل الإنتاج قبل Phase A؟ | لو نعم، فكل «الإصلاحات» غير موجودة فعليًا في الإنتاج |
| **B-4** | **حذف نقاط الكشف** (`/whatsapp/Token/{id}`, `/send-whatsapp`, `info.php`, `/subscription/success`) | كشف بيانات ورموز مستأجرين |
| **B-5** | **إصلاح دورة حياة الاشتراك** (BI-01 + BI-02 + BI-10 + BI-09) | عميل يدفع ولا يحصل على شيء؛ وغير الدافع لا يُقيَّد أبدًا |
| **B-6** | **حسم `INSTALLATION_PRICING_PLAN` و`ChatwootApp.enterprise?`** | لو `community`، الميزات تُمسح يوميًا؛ لو غير enterprise، الحدود مُتجاهَلة |
| **B-7** | **Staging يعمل + CI/CD ببوابة** | يوقف التطوير على الإنتاج |
| **B-8** | **نسخة احتياطية مُثبَت استرجاعها** | تدوير `APP_KEY` بلا نسخة مُختبَرة = خطر فقد بيانات |
| **B-9** | **التحقق التشغيلي للقنوات** | لا يجوز تسويق قناة لم تُختبَر طرفيًا |
| **B-10** | **رأي قانوني في تشغيل Chatwoot EE** | `enterprise/` مُفعَّل — له تبعات ترخيصية |

### 20.2 UNVERIFIED / BLOCKED — بصراحة كما طلبتَ

| السؤال | الحالة | ما يلزم |
|---|---|---|
| هل الإنتاج يشغّل الكود المُدقَّق؟ | 🔴 UNVERIFIED | `git rev-parse HEAD` + `migrate:status` |
| هل دُوِّرت الاعتمادات؟ | 🔴 UNVERIFIED (المؤشرات: **لا**) | لوحات المزودين |
| ما القنوات المُهيّأة فعلًا؟ | 🔴 BLOCKED | `Inbox.group(:channel_type).count` |
| هل Push يعمل؟ | 🔴 BLOCKED | `ENABLE_PUSH_RELAY_SERVER` + `FIREBASE_CREDENTIALS` + اختبار جهاز |
| هل التشفير مفعّل؟ | 🔴 BLOCKED | `ACTIVE_RECORD_ENCRYPTION_*` |
| هل توجد نسخ احتياطية؟ | 🔴 UNVERIFIED | وصول للخادم |
| هل CI الأخير أخضر فعلًا؟ | 🔴 UNVERIFIED | GitHub Actions run 34162936154 |
| أيّ مسار WhatsApp حيّ — Zender أم Meta؟ | 🔴 BLOCKED | جرد الـ Inboxes |

---

## 21. Architecture Decisions Required — قرارات معمارية مطلوبة منك

**لا يمكنني اتخاذ هذه — إنها قرارات منتج/عمل.**

| # | القرار | الخيارات | توصيتي |
|---|---|---|---|
| **AD-1** | **مصدر الحقيقة للهوية** | (أ) Central كـ IdP وChatwoot تابع · (ب) الوضع الحالي | **(أ)** — البنية موجودة (`ssoUrl`)؛ ينقص تعريضها للموبايل |
| **AD-2** | **إنهاء تمرير كلمة المرور** | (أ) `/api/sso/chat` + تبادل رمز · (ب) الإبقاء | **(أ)** مع fallback ونافذة تبنٍّ |
| **AD-3** | **معمارية WhatsApp** | (أ) Zender · (ب) Meta Cloud أصلي · (ج) كلاهما | **يحتاج قرارك.** (أ) نص فقط بلا وسائط ولا قوالب ولا حالات. (ب) قدرات كاملة لكن يتطلب موافقات Meta |
| **AD-4** | **قناة شراء العميل** | (أ) صفحة في Central · (ب) إعادة تفعيل فوترة Chatwoot · (ج) الموبايل فقط | **(أ)** — أقل تعارضًا مع Upstream ويحل BI-08 |
| **AD-5** | **`INSTALLATION_PRICING_PLAN`** | (أ) enterprise · (ب) حجب hub · (ج) community | **(أ) أو (ب)** — وإلا فمزامنة الميزات مستحيلة |
| **AD-6** | **نطاق المنظومة** | Chat وحده أم المنظومة الخماسية | يحدد حجم Phase 2 كليًا |
| **AD-7** | **القيد الفريد على رقم الهاتف** | (أ) تركه · (ب) ترحيل لكل حساب | **(أ) مؤجَّل** — غير عاجل، خصوصًا لو المسار Zender |
| **AD-8** | **ترخيص Chatwoot EE** | مراجعة قانونية | **مطلوب قبل الإطلاق التجاري** |

---

## 22. Recommended Phase 2 Execution Plan — خطة التنفيذ المقترحة

### Phase 2.0 — احتواء الطوارئ (3–5 أيام) 🔴
1. **تدوير كل الاعتمادات الـ 38** عبر لوحات المزودين. `APP_KEY` **أخيرًا** مع إعادة تشفير.
2. حذف `/whatsapp/Token/{id}` · `/send-whatsapp` · `public/info.php` · إصلاح `/subscription/success`.
3. إضافة تحقق ID token لـ Google/Apple + `throttle` على كل نقاط المصادقة.
4. إصلاح `platform_secret` (توليد وتخزين بدل الاشتقاق).
5. **حسم حالة النشر** ونشر Phases A–G1 إن لم تكن منشورة.
6. تطهير تاريخ Git **بعد** التدوير.

> لا شيء آخر يبدأ قبل اكتمال هذه.

### Phase 2.1 — الأساس التشغيلي (1–2 أسبوع)
Staging يعمل (إصلاح العيوب الثلاثة) · CI/CD ببوابة للمستودعات الثلاثة · Sentry في الثلاثة · **نسخة احتياطية مع استرجاع مُثبَت على Staging** · إيقاف التطوير على الإنتاج نهائيًا.

### Phase 2.2 — التحقق التشغيلي (1 أسبوع) — ما عجزتُ عنه هنا
تنفيذ قوائم §6.2 و§8.1 · ملء مصفوفة القنوات بقيم حقيقية · حسم `enterprise?` و`pricing_plan` و`ENABLE_PUSH_RELAY_SERVER` · تحديد مسار WhatsApp الحيّ.

### Phase 2.3 — سلامة الفوترة (2–3 أسابيع)
إصلاح BI-01/02/03/06 · تصحيح أسماء الميزات مع **جدول تحقق مقابل `features.yml`** · بناء `EntitlementReconciler` (تعليق/خفض/انتهاء/مهلة سماح) · معالجة CW-01 وCW-02 · إنفاذ حد الـ Inboxes على المسارات التسعة · **اختبار عقد بين المحاكي و`features.yml` الحقيقي**.

### Phase 2.4 — توحيد الهوية (2–3 أسابيع)
`/api/sso/chat` في Central · تبنّي الموبايل مع fallback · عزل Dio · انتهاء صلاحية وإبطال رموز Sanctum · تسجيل `chatwoot_account_id` في مسارَي Google/Apple · **ثم** حذف تمرير كلمة المرور.

### Phase 2.5 — موثوقية الموبايل (2–3 أسابيع)
واجهة تسجيل + قاعدة `avoid_print` · `flutter_secure_storage` بترحيل · `allowBackup=false` · معالجة 401/403/429 في المواضع الثمانية · Pagination · إعادة مزامنة WS + حارس إعادة اتصال · إصلاح MB-02 · إصلاح Apple (platform + entitlement + Firebase) · **أول اختبارات + CI**.

### Phase 2.6 — تقليل الانحراف عن Upstream (1 أسبوع)
تنفيذ §18.3 (7 ملفات ← 2) · إعداد فروع §18.4 · **أول merge على staging فقط**.

**الترتيب ملزم:** الأمن ← البنية ← التحقق ← الفوترة ← الهوية ← الموبايل ← Upstream.
**لا ميزات جديدة، ولا إعادة تصميم واجهات، قبل انتهاء 2.3** — كما اشترطتَ في §21.

---

## 23. Definition of Done — الإجابات المباشرة

| # | السؤال | الجواب |
|---|---|---|
| 1 | **أين Source Code الخاص بـ lynomia.com؟** | ✅ **`fullstackfull/lynomia98`** — Laravel 13.8، فرع `main`، مُدقَّق بالكامل |
| 2 | **من هو Identity Source of Truth؟** | ✅ **Central (`lynomia98`)**. يُنشئ مستخدم وحساب Chatwoot عبر Platform API |
| 3 | **من هو Subscription Source of Truth؟** | ✅ **Central** — `billing_subscriptions` + `accounts_subscriptions_chat` |
| 4 | **كيف يصل الاشتراك إلى Chatwoot؟** | ✅ `PATCH /platform/api/v1/accounts/{id}` بـ `{limits, features, status}` عبر `ChatwootConnector`. **الحدود والتعليق يعملان؛ الميزات مكسورة (أسماء غير صالحة)؛ ولا يوجد أي إلغاء أو تخفيض** |
| 5 | **ما القنوات المُهيّأة فعلًا؟** | 🔴 **BLOCKED** — الشبكة محجوبة. قائمة التحقق جاهزة في §6.2 |
| 6 | **ما القنوات المُختبَرة E2E؟** | 🔴 **لا شيء.** لم تُرسَل أي رسالة. الإجراء الآمن في §8.1 |
| 7 | **هل Push يعمل؟** | 🔴 **UNVERIFIED.** ويوجد خطر محدد: `ENABLE_PUSH_RELAY_SERVER` قد يوجّه الإشعارات لتطبيقات Chatwoot الرسمية |
| 8 | **هل Encryption مفعّل؟** | 🔴 **UNVERIFIED** لـ Chatwoot. ✅ Central **يشفّر** اعتمادات المستأجرين — لكن `APP_KEY` **مكشوف في Git** ⇒ التشفير بلا قيمة حتى التدوير |
| 9 | **هل Staging موجود؟** | ⚠️ **يوجد ملف لكنه لا يعمل** — 3 عيوب P1 مؤكَّدة (§13.1) |
| 10 | **هل هناك CI/CD حقيقي؟** | ⚠️ **Central: نعم** (ببوابات أمنية). **Chatwoot: workflows موروثة بلا قيمة. الموبايل: لا شيء.** ولا نشر آلي في أي منها |
| 11 | **هل لدينا Backup مُختبَر بالاسترجاع؟** | 🔴 **UNVERIFIED** — لا دليل على وجود نسخ أصلًا |
| 12 | **هل أوقفنا أخطر تسريبات الموبايل؟** | ✅ **نعم لتسريب الاعتمادات** (commits `e94e958` + `3eeae33`). ❌ التخزين غير الآمن وتسريب رأس Chatwoot **لم يُعالَجا بعد** — يحتاجان اختبار انحدار |
| 13 | **هل لدينا خطة تمنع Fork drift؟** | ✅ **نعم** (§18) — مع تصحيح: `custom/` **hook ميت**، والبديل هو Custom Branding + `scoped` + حذف تخصيصين زائدين ⇒ **7 ملفات ← 2** |

---

## 24. خلاصة Phase 1

**ما تغيّر جذريًا عن Phase 0:**

Lynomia Chat **ليس** ثلاثة أنظمة، بل **منتج واحد داخل منظومة خماسية** يديرها حساب مركزي (Laravel). النظام «المجهول» في Phase 0 وُجِد، ودُقِّق، واتضح أنه **الأنضج هندسيًا من ناحية التكامل** (طبقة Connectors، توقيع HMAC، حماية تكرار، CI ببوابات أمنية، 141 وثيقة) — **وفي الوقت نفسه الأضعف أمنيًا** (ثغرات استيلاء على الحسابات، واعتمادات إنتاج مكشوفة).

**الخبر الجيد:** الجسر الذي قال Phase 0 إنه غير موجود — **موجود ويعمل جزئيًا**. الحدود تُفرَض فعلًا. آلية SSO الآمنة (بلا كلمة مرور) **مبنية بالفعل** وتحتاج فقط تعريضها للموبايل. الانحراف عن Chatwoot ما زال ضئيلًا وقابلًا للتقليص إلى ملفين.

**الخبر الصعب:** ثلاث حقائق تتفوق على كل ما عداها:
1. **38 اعتماد إنتاج حيّ مكشوف في تاريخ Git وغير مُدوَّر** — من ضمنه مفتاح تحكم كامل في Chatwoot ومفتاح يفكّ كل التشفير.
2. **ثغرتان تسمحان بالاستيلاء على أي حساب بطلب واحد غير مُصادَق.**
3. **الكود المُصلَح قد لا يكون منشورًا أصلًا** — تقرير المستودع نفسه يقول إن الإنتاج «byte-for-byte pre-Phase-A».

**وحقيقة منهجية:** من كل نتيجتين حرجتين خضعتا لمراجعة مستقلة، **واحدة دُحِضت أو خُفِّضت**. بما فيها استنتاج توصّلتُ إليه بنفسي ودحضته المراجعة. هذا هو المكسب الحقيقي من §22 — وهو سبب كافٍ لعدم اتخاذ أي قرار معماري كبير قبل مراجعة ثانية.

**لم يُنفَّذ أي تغيير معماري. لم يُلمَس أي تكامل قائم. لم يُكسَر أي Feature.**

**في انتظار قراراتك في §21 قبل الانتقال إلى Phase 2.**
