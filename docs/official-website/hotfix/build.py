#!/usr/bin/env python3
"""Build the P0 hotfix page from the snapshot of the live site.

WHY A BUILD SCRIPT AND NOT A HAND-EDITED FILE. The live page is 100,208 bytes of hand-written HTML with all
CSS and copy inline, and it is not in version control anywhere else. Transforming it with asserted
replacements makes every change reviewable (this file IS the change list), reproducible (re-run it and get the
same bytes), and safe (a replacement whose anchor text has moved raises instead of silently doing nothing).

INPUT   docs/official-website/hotfix/snapshot-2026-09-12.html
        A byte-identical copy of https://chat.lynomia.com/ fetched 2026-10-14, named for the file's own
        last-modified date on the server. sha256 0b88ed7529afaae994df581e24a9e884a67b361cf8a3422d87e21bbfb76d8810
OUTPUT  docs/official-website/hotfix/index.html

WHAT THIS FIXES, and the audit finding each item closes (docs/official-website/01-current-state-audit.md):
  F2  dead trial CTA           -> every call to action points at a destination that answers 200
  F3  simulated live chat      -> a contact card with a working mailto:, the docs and sign-in
  F4  forced Arabic->English   -> language is the visitor's stored choice; Arabic stays Arabic
  F5  fabricated status panel  -> a factual security-posture panel with no live framing
  F6  AI claims                -> the five real agent-assist actions, with their prerequisite stated
  F8  missing head tags        -> description, canonical, Open Graph, Twitter, icon
  F10 legal documents with no URL -> links to the existing approved pages on lynomia.com
  plus: the "+10 channels" and "24/7 AI" proof points, the voice-calls channel pill, and the malformed
        footer list markup.

NOT CHANGED, deliberately: the visual identity (every colour token, font, layout rule and SVG is untouched),
the product mock-up in the hero, and the page's structure. This is a claim and link correction, not a redesign;
the redesign is the Rails site being built under docs/official-website/04-information-architecture.md.
"""

import hashlib
import io
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE / 'snapshot-2026-09-12.html'
DST = HERE / 'index.html'
SRC_SHA = '0b88ed7529afaae994df581e24a9e884a67b361cf8a3422d87e21bbfb76d8810'

# Verified destinations only. Each was checked with a live GET on 2026-10-14 and the status is recorded in
# docs/official-website/01-current-state-audit.md; the four legal pages are the operator's own approved
# documents on the corporate domain (no policy text is invented here).
REGISTER = '/app/register'                                  # 200, and ENABLE_ACCOUNT_SIGNUP is true in production
LOGIN = '/app/login'                                        # 200
DOCS = '/docs'                                              # 302 -> /hc/lynomia-docs/en, 75 articles live
CHANGELOG = '/changelog'                                    # 302 -> /hc/lynomia-changelog
MAIL = 'mailto:info@lynomia.com'                            # the address already printed on the page, now clickable
L_ABOUT = 'https://lynomia.com/about_us'                    # 200, 7,570 B
L_PRIVACY = 'https://lynomia.com/privacy'                   # 200, 16,886 B
L_DELETION = 'https://lynomia.com/user-data-deletion'       # 200, 10,703 B
L_TERMS = 'https://lynomia.com/terms'                       # 200, 18,266 B

edits = []


def sub(old, new, note, count=1):
    edits.append((old, new, note, count))


# --------------------------------------------------------------------------------------------------------
# 1. HEAD — the tags the page had none of (F8). No hreflang: there is still only one URL, and a self-
#    referential hreflang pair would be a claim about pages that do not exist yet.
# --------------------------------------------------------------------------------------------------------
sub(
    '<title>Lynomia Chat — كل محادثات عملائك بصندوق واحد</title>',
    '<title>Lynomia Chat — كل محادثات عملائك بصندوق واحد</title>\n'
    '<meta name="description" content="لنوميا شات تجمع محادثات واتساب وإنستغرام وماسنجر وتيليجرام '
    'والبريد وشات موقعك في صندوق وارد واحد لفريقك، مع توزيع تلقائي وتقارير ومركز مساعدة بالعربي '
    'والإنجليزي.">\n'
    f'<link rel="canonical" href="https://chat.lynomia.com/">\n'
    '<meta property="og:type" content="website">\n'
    '<meta property="og:site_name" content="Lynomia Chat">\n'
    '<meta property="og:url" content="https://chat.lynomia.com/">\n'
    '<meta property="og:title" content="Lynomia Chat — كل محادثات عملائك بصندوق واحد">\n'
    '<meta property="og:description" content="صندوق وارد موحّد لقنوات محادثات عملائك، لفرق الدعم '
    'والمبيعات.">\n'
    '<meta property="og:image" content="https://lynomia.com/img/new/lynomia-icon.png">\n'
    '<meta name="twitter:card" content="summary">\n'
    '<link rel="icon" href="https://lynomia.com/img/new/lynomia-icon.png">',
    'head: description, canonical, Open Graph, Twitter card, icon',
)

# --------------------------------------------------------------------------------------------------------
# 2. NAV — a documentation link, because /docs is live with 75 articles and the page never linked it.
# --------------------------------------------------------------------------------------------------------
sub(
    '      <a href="#security" data-i="n6">الأمان</a>\n',
    '      <a href="#security" data-i="n6">الأمان</a>\n'
    f'      <a href="{DOCS}" data-i="n7">الوثائق</a>\n',
    'nav: add the documentation link',
)

# --------------------------------------------------------------------------------------------------------
# 3. HERO CTA (F2) — "try it free" pointed at an in-page anchor. Signup is enabled in production.
# --------------------------------------------------------------------------------------------------------
sub(
    '        <a class="btn btn-primary" href="#cta"><span data-i="cta1">جرّبها مجانًا</span>',
    f'        <a class="btn btn-primary" href="{REGISTER}"><span data-i="cta1">أنشئ حسابك</span>',
    'hero: primary CTA -> /app/register',
)

# --------------------------------------------------------------------------------------------------------
# 4. HERO PROOF POINTS — "+10 channels" counted voice calls, which do not exist; "24/7 AI auto-replies"
#    describes a product that is off by default and unsellable (F6). Replaced with three facts that can be
#    checked: nine connectable channels, the 57 locale bundles the agent dashboard ships, and the public API.
# --------------------------------------------------------------------------------------------------------
sub(
    '        <div class="proof"><b>+10</b><span data-i="pr1">قنوات بصندوق واحد</span></div>\n'
    '        <div class="proof"><b>50+</b><span data-i="pr2">لغة مع ترجمة فورية</span></div>\n'
    '        <div class="proof"><b>24/7</b><span data-i="pr3">ردود آلية بالذكاء الاصطناعي</span></div>\n',
    '        <div class="proof"><b>9</b><span data-i="pr1">قنوات تربطها بصندوق واحد</span></div>\n'
    '        <div class="proof"><b>50+</b><span data-i="pr2">لغة لواجهة الوكلاء</span></div>\n'
    '        <div class="proof"><b>API</b><span data-i="pr3">وويب هوكس للربط بأنظمتك</span></div>\n',
    'hero: proof points -> verified figures',
)

# --------------------------------------------------------------------------------------------------------
# 5. CHANNEL STRIP — drop the voice-calls pill (no Channel::Voice exists; the tiles were removed from the
#    product) and label TikTok as beta, which is what the dashboard itself calls it.
# --------------------------------------------------------------------------------------------------------
sub(
    "chNames:['شات الموقع','واتساب API','إنستغرام DM','فيسبوك ماسنجر','تيليجرام','تيك توك',"
    "'الإيميل','رسائل SMS','LINE','مكالمات صوتية']",
    "chNames:['شات الموقع','واتساب API','إنستغرام DM','فيسبوك ماسنجر','تيليجرام','تيك توك',"
    "'الإيميل','رسائل SMS','LINE']",
    'channels: remove the voice-calls pill (Arabic)',
)
sub(
    "chNames:['Website chat','WhatsApp API','Instagram DM','Facebook Messenger','Telegram','TikTok',"
    "'Email','SMS','LINE','Voice calls']",
    "chNames:['Website chat','WhatsApp API','Instagram DM','Facebook Messenger','Telegram','TikTok',"
    "'Email','SMS','LINE']",
    'channels: remove the voice-calls pill (English)',
)
sub(
    """    ['var(--chat-tint)','<path fill="var(--chat)" d="M6.6 10.8a15 15 0 0 0 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.2.4 2.4.6 3.7.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1A17 17 0 0 1 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.2.2 2.5.6 3.6.1.4 0 .8-.2 1l-2.3 2.2Z"/>',1],\n""",
    '',
    'channels: remove the voice-calls icon entry so names and icons stay aligned',
)
sub("soon:'قريبًا',", "soon:'تجريبي',", 'channels: the badge now reads "beta" rather than "soon" (Arabic)')
sub("soon:'soon',", "soon:'beta',", 'channels: the badge now reads "beta" rather than "soon" (English)')

# --------------------------------------------------------------------------------------------------------
# 6. AI SECTION (F6) — the largest correction. There is no AI assistant, agent, copilot or chatbot in the
#    product: what exists is five agent-assist actions behind an account flag that is OFF by default and a
#    customer-supplied OpenAI key. The section now sells exactly that, says what it needs, and drops the
#    autonomous-resolution card entirely.
# --------------------------------------------------------------------------------------------------------
sub(
    '      <span class="sec-kick">AI ASSISTANT</span>\n'
    '      <h2 data-i="aih2">ذكاء اصطناعي يردّ بدالك… ويساعد فريقك لما يردّ بنفسه</h2>\n'
    '      <p data-i="aipp">الوكيل الذكي يتعلّم من مركز مساعدتك ومحادثاتك السابقة، فيحلّ الأسئلة المتكررة لحاله — وأي محادثة أعقد، بيكون جنب وكيلك باقتراحات وردود وترجمة فورية.</p>',
    '      <span class="sec-kick">AI ASSIST FOR AGENTS</span>\n'
    '      <h2 data-i="aih2">مساعدة ذكية لوكلائك — وهم من يضغط «إرسال»</h2>\n'
    '      <p data-i="aipp">خمس أدوات مساعدة داخل صندوق الوارد: إعادة صياغة الرد، تلخيص المحادثة، اقتراح رد، '
    'اقتراح تصنيفات، وصياغة رسالة متابعة. تُفعَّل لحسابك عند ربط مفتاح OpenAI الخاص بك، ولا ترسل أي رسالة '
    'تلقائيًا من دون موافقة وكيلك.</p>',
    'ai: section heading and lede -> the five real actions and their prerequisite',
)
sub(
    '        <h3 data-i="ac1h">ردود آلية 24/7</h3>\n'
    '        <p data-i="ac1p">يجاوب على الأسئلة المتكررة فورًا من قاعدة معرفتك — وينقل المحادثة لوكيل بشري لما يحتاج الموضوع لمسة إنسانية.</p>',
    '        <h3 data-i="ac1h">إعادة صياغة وتلخيص</h3>\n'
    '        <p data-i="ac1p">حسّن صياغة ردّك قبل إرساله، أو لخّص محادثة طويلة في سطور قليلة قبل تحويلها '
    'لزميل — والنص النهائي يبقى بيد وكيلك.</p>',
    'ai: card 1 -> rewrite and summarise, replacing the autonomous-resolution claim',
)
sub(
    '          <div class="mrow"><span class="bub q" data-i="ac1q">كيف أغيّر كلمة المرور؟</span></div>\n',
    '          <div class="mrow"><span class="bub q" data-i="ac1q">المسودة: «ما نقدر نساعدك بهذا الطلب.»</span></div>\n',
    'ai: card 1 demo question -> a draft being improved',
)
sub(
    '          <div class="mrow"><span class="bub a" data-i="ac1a">من الإعدادات ← الحساب ← تغيير كلمة المرور. بعتلك رابط الشرح المفصّل 👌</span></div>\n'
    '          <div class="mrow"><span class="tag" data-i="ac1t">حُلّت آليًا · بدون تدخل بشري</span></div>\n',
    '          <div class="mrow"><span class="bub a" data-i="ac1a">بعد إعادة الصياغة: «هذا الطلب خارج ما '
    'نقدر ننفّذه حاليًا، وهذا البديل الذي نقترحه…»</span></div>\n'
    '          <div class="mrow"><span class="tag" data-i="ac1t">اقتراح للوكيل · الإرسال يدوي</span></div>\n',
    'ai: card 1 demo answer -> suggestion, sent by a human',
)
sub(
    '        <h3 data-i="ac3h">ترجمة فورية · 50+ لغة</h3>',
    '        <h3 data-i="ac3h">ترجمة الرسائل · تتطلب إعدادًا</h3>',
    'ai: card 3 -> translation labelled as requiring configuration',
)
sub(
    '        <p data-i="ac3p">العميل يكتب بلغته، ووكيلك يقرأ ويردّ بلغته هو — الترجمة تصير بالخلفية بدون ما ي',
    '        <p data-i="ac3p">ترجمة رسالة واحدة عند الطلب داخل المحادثة، بعد ربط حساب Google Translate '
    'الخاص بك. غير مُفعّلة تلقائيًا، ولا تُترجم المحادثات كلها بالخلفية. وواجهة الوكلاء نفسها متوفرة بأكثر '
    'من 50 لغة. <!--',
    'ai: card 3 body -> the real translation behaviour and its prerequisite',
)

# --------------------------------------------------------------------------------------------------------
# 7. SECURITY SECTION (F5) — four fabricated readouts and an "every action is logged" claim that the
#    product's own documentation contradicts. Every line below is sourced in
#    docs/official-website/02-verified-feature-inventory.md section 6.1.
# --------------------------------------------------------------------------------------------------------
sub(
    '      <span class="sec-kick">ENTERPRISE SECURITY</span>\n'
    '      <h2 data-i="sh2">أمان على مستوى المؤسسات — وبيانات عملائك ملكك</h2>\n'
    '      <p class="d" data-i="sp">تشفير كامل أثناء النقل والتخزين، صلاحيات دقيقة لكل عضو بالفريق، وسجلّ تدقيق لكل إجراء — محادثات عملائك تبقى تحت سيطرتك الكاملة.</p>',
    '      <span class="sec-kick">SECURITY &amp; ACCESS CONTROL</span>\n'
    '      <h2 data-i="sh2">عزل كامل بين الحسابات — وبيانات عملائك ملكك</h2>\n'
    '      <p class="d" data-i="sp">اتصال مشفّر عبر HTTPS مع HSTS، بيانات اعتماد القنوات مشفّرة في التخزين، '
    'صلاحيات دقيقة لكل عضو، وسجلّ تدقيق لتغييرات الإعدادات وتسجيلات الدخول لا يستطيع صاحب الإجراء '
    'تعطيله.</p>',
    'security: heading and lede -> substantiated wording',
)
sub(
    '<div><b data-i="s1h">تشفير كامل</b><span data-i="s1p">أثناء النقل وفي التخزين، مع نسخ احتياطي يومي.</span></div>',
    '<div><b data-i="s1h">تشفير أثناء النقل</b><span data-i="s1p">HTTPS مع HSTS، وبيانات اعتماد القنوات '
    'والمتاجر مشفّرة في التخزين.</span></div>',
    'security: shield 1 -> transit encryption plus encrypted credentials',
)
sub(
    '<div><b data-i="s3h">سجلّ تدقيق</b><span data-i="s3p">كل إجراء بالحساب مسجّل ومتتبّع — للحوكمة والامتثال.</span></div>',
    '<div><b data-i="s3h">سجلّ تدقيق</b><span data-i="s3p">تغييرات الإعدادات وتسجيلات الدخول مسجّلة، '
    'ويُحفظ السجلّ 365 يومًا بشكل افتراضي.</span></div>',
    'security: shield 3 -> what the audit trail actually records',
)
sub(
    '        <div class="hd"><span class="pink">●</span> lynomia-chat / system status</div>\n'
    '        <div class="hrow">app · chat.lynomia.com <span class="ok">online</span></div>\n'
    '        <div class="hrow">encryption · TLS 1.3 + AES-256 <span class="ok">active</span></div>\n'
    '        <div class="hrow">backups · daily 03:00 <span class="ok">done</span></div>\n'
    '        <div class="hrow">uptime · last 90 days <span class="ok">99.98%</span></div>\n'
    '        <div class="hrow">monitoring · security & health <span class="ok">24/7</span></div>\n',
    '        <div class="hd"><span class="pink">●</span> lynomia-chat / security posture</div>\n'
    '        <div class="hrow">transport <span class="val">HTTPS + HSTS</span></div>\n'
    '        <div class="hrow">channel credentials <span class="val">encrypted at rest</span></div>\n'
    '        <div class="hrow">tenant isolation <span class="val">enforced server-side</span></div>\n'
    '        <div class="hrow">database backup <span class="val">verified before each deploy</span></div>\n'
    '        <div class="hrow">audit trail <span class="val">config changes &amp; sign-ins</span></div>\n',
    'security: the fabricated live-status panel -> a factual posture panel',
)
# The .ok class pulses, which is what made static text read as a live readout. .val is a static chip.
sub(
    '  /* ---------- reveal on scroll ---------- */',
    '  /* A static value chip. The panel it belongs to used to style hard-coded text as a live system\n'
    '     readout with pulsing dots; these values are statements of posture, so they must not animate. */\n'
    '  .host-card .val{color:#9fe7c0;font-weight:600}\n\n'
    '  /* ---------- reveal on scroll ---------- */',
    'security: add the non-animated .val chip style',
)

# --------------------------------------------------------------------------------------------------------
# 8. CLOSING CTA (F2, F5) — the button opened the simulated widget and the hint promised a trial that
#    cannot start: no BillingPlan row exists and BILLING_TRIAL_PLAN_ID defaults to nil.
# --------------------------------------------------------------------------------------------------------
sub(
    '      <p data-i="ctap">فعّل Lynomia Chat لفريقك خلال يوم واحد — نربطلك قنواتك وواتساب API، نجهّز الردود الآلية، وندرّب فريقك على اللوحة.</p>\n'
    '      <a class="btn btn-chat" href="#" onclick="toggleWidget(true);return false"><span data-i="ctab">احكِ معنا الآن</span>',
    '      <p data-i="ctap">اربط قنواتك في صندوق وارد واحد، ووزّع المحادثات على فريقك، وتابع الأداء '
    'بالتقارير. الوثائق بالعربي والإنجليزي جاهزة، وفريقنا يساعدك في الإعداد.</p>\n'
    f'      <a class="btn btn-chat" href="{REGISTER}"><span data-i="ctab">أنشئ حسابك</span>',
    'cta: button -> /app/register with accurate copy',
)
sub(
    '      <span class="hint" data-i="ctahint">تجربة مجانية · بدون بطاقة ائتمانية · دعم بالعربي</span>',
    '      <span class="hint" data-i="ctahint">عندك سؤال قبل ما تبدأ؟ '
    f'<a href="{MAIL}" style="text-decoration:underline">راسلنا</a> أو اقرأ '
    f'<a href="{DOCS}" style="text-decoration:underline">الوثائق</a>.</span>',
    'cta: hint -> real contact and documentation links instead of a trial promise',
)

# --------------------------------------------------------------------------------------------------------
# 9. FOOTER — product column gains the two live public routes; the contact column loses the simulated chat
#    and gains a working mailto:; the legal column is rebuilt as real links to the operator's approved
#    pages, and its malformed markup (`<li></li> <a …></li>`) is corrected.
# --------------------------------------------------------------------------------------------------------
sub(
    '          <li><a href="#reports" data-i="fl4">التقارير</a></li>\n',
    '          <li><a href="#reports" data-i="fl4">التقارير</a></li>\n'
    f'          <li><a href="{DOCS}" data-i="fl5">الوثائق ومركز المساعدة</a></li>\n'
    f'          <li><a href="{CHANGELOG}" data-i="fl6">سجل التحديثات</a></li>\n',
    'footer: product column -> add documentation and changelog',
)
sub(
    '''          <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16v12H4z"/><path d="m4 7 8 6 8-6"/></svg><span class="mono" dir="ltr">info@lynomia.com</span></li>''',
    f'''          <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16v12H4z"/><path d="m4 7 8 6 8-6"/></svg><a class="mono" dir="ltr" href="{MAIL}">info@lynomia.com</a></li>''',
    'footer: the email address becomes a working mailto: link',
)
sub(
    '''          <li><svg viewBox="0 0 24 24" fill="currentColor"><path d="M21 11.5a8.4 8.4 0 0 1-8.5 8.3c-1.5 0-2.9-.36-4.1-1L3 20l1.3-4.9A8.1 8.1 0 0 1 3.5 11.5 8.4 8.4 0 0 1 12 3.2a8.4 8.4 0 0 1 9 8.3Z"/></svg><a href="#" onclick="toggleWidget(true);return false" data-i="flchat">شات مباشر — نرد خلال دقائق</a></li>''',
    f'''          <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-3.6 8-10V5l-8-3-8 3v7c0 6.4 8 10 8 10Z"/></svg><a href="{LOGIN}" data-i="flchat">سجّل الدخول لفتح تذكرة دعم</a></li>''',
    'footer: simulated live chat -> sign in to open a support ticket',
)
sub(
    ''' <div class="footer-links">
   <li></li> <a href="#about" onclick="openModal('about')" data-i="pb1">من نحن</a></li>
   <li></li> <a href="#privacy" onclick="openModal('privacy')" data-i="pb2">سياسة الخصوصية</a></li>
      <li></li> <a href="#deletion" onclick="openModal('deletion')" data-i="pb3"> حذف البيانات</a></li>

   <li></li> <a href="#terms" onclick="openModal('terms')" data-i="pb4">شروط الاستخدام</a></li>
  </div>
''',
    f''' <div class="footer-links">
   <li><a href="{L_ABOUT}" target="_blank" rel="noopener" data-i="pb1">من نحن</a></li>
   <li><a href="{L_PRIVACY}" target="_blank" rel="noopener" data-i="pb2">سياسة الخصوصية</a></li>
   <li><a href="{L_DELETION}" target="_blank" rel="noopener" data-i="pb3">حذف البيانات</a></li>
   <li><a href="{L_TERMS}" target="_blank" rel="noopener" data-i="pb4">شروط الاستخدام</a></li>
  </div>
''',
    'footer: legal links -> the approved pages on lynomia.com, with valid list markup',
)

# --------------------------------------------------------------------------------------------------------
# 10. THE SIMULATED CHAT WIDGET (F3) — it claimed a human was online with a two-minute average reply and
#     sent nothing anywhere: the served file contains no fetch, XHR, WebSocket, mailto, tel or wa.me. The
#     floating panel is kept, because it is part of the page's identity, and every control in it now works.
# --------------------------------------------------------------------------------------------------------
sub(
    '''<div class="widget" id="widget" role="dialog" aria-label="شات مباشر">
  <div class="w-head">
    <b data-i="wh1">أهلًا بك 👋</b>
    <span data-i="wh2">فريق لنوميا متصل — متوسط الرد: دقيقتين</span>
  </div>
  <div class="w-body" id="wBody">
    <div class="msg cust" data-i="wm1">مرحبا! هذا نفس الويدجت اللي بينركّب على موقعك — بألوانك وبلغتك.</div>
    <div class="msg agent" data-i="wm2">اسألنا أي شي عن المنصة، أو اطلب عرضًا تجريبيًا لفريقك 🙌</div>
  </div>
  <div class="w-foot">
    <input id="wInput" type="text" placeholder="اكتب رسالتك…" aria-label="اكتب رسالتك">
    <button onclick="sendW()" aria-label="إرسال">
      <svg class="flip" viewBox="0 0 24 24" fill="currentColor"><path d="m3 11 18-8-8 18-2-8-8-2Z"/></svg>
    </button>
  </div>
</div>''',
    f'''<div class="widget" id="widget" role="dialog" aria-label="تواصل مع لنوميا">
  <div class="w-head">
    <b data-i="wh1">تواصل معنا 👋</b>
    <span data-i="wh2">اختر الطريقة الأنسب لك</span>
  </div>
  <div class="w-body" id="wBody">
    <div class="msg agent" data-i="wm1">للأسئلة قبل الاشتراك: راسلنا على البريد ونرد عليك.</div>
    <div class="msg cust" data-i="wm2">عميل حالي؟ سجّل الدخول وافتح تذكرة دعم من «المساعدة والدعم».</div>
  </div>
  <div class="w-foot" style="display:flex;gap:8px;flex-wrap:wrap">
    <a class="btn btn-primary" style="flex:1 1 auto;justify-content:center" href="{MAIL}" data-i="wb1">راسلنا بالبريد</a>
    <a class="btn btn-ghost" style="flex:1 1 auto;justify-content:center" href="{DOCS}" data-i="wb2">الوثائق</a>
  </div>
</div>''',
    'widget: simulated chat -> a contact card whose every control works',
)
sub('  <span class="badge">1</span>\n', '', 'widget: remove the fake unread badge')
sub(
    '<button class="fab" id="fab" onclick="toggleWidget()" aria-label="افتح الشات المباشر">',
    '<button class="fab" id="fab" onclick="toggleWidget()" aria-label="تواصل مع لنوميا">',
    'widget: the launcher no longer advertises a live chat',
)

# --------------------------------------------------------------------------------------------------------
# 11. JAVASCRIPT — remove the send simulation, the input wiring, and the forced language flip.
# --------------------------------------------------------------------------------------------------------
sub(
    '''  let ri = 0;
  function sendW(){
    const inp = document.getElementById('wInput'), body = document.getElementById('wBody');
    const v = inp.value.trim(); if(!v) return;
    body.insertAdjacentHTML('beforeend', `<div class="msg cust"></div>`);
    body.lastElementChild.textContent = v;
    inp.value = '';
    body.scrollTop = body.scrollHeight;
    setTimeout(()=>{
      body.insertAdjacentHTML('beforeend', `<div class="msg agent"></div>`);
      body.lastElementChild.textContent = T[cur].replies[ri++ % T[cur].replies.length];
      body.scrollTop = body.scrollHeight;
    }, 800);
  }
  document.getElementById('wInput').addEventListener('keydown', e=>{ if(e.key==='Enter') sendW() });''',
    '''  /* LANGUAGE IS THE VISITOR'S CHOICE, read once here.
     The previous build clicked the language button unconditionally on DOMContentLoaded, so every visitor to
     an Arabic-first page was flipped to English on every load, with lang and dir changing under them. The
     document is served in Arabic; only a stored English preference changes it. */
  try { if (localStorage.getItem('lang') === 'en') setLang('en'); } catch (e) { /* storage unavailable */ }''',
    'js: remove the chat simulation and read the stored language preference instead of forcing a flip',
)
sub(
    '''    const langBtn = document.getElementById('langBtn'); // تأكد أن هذا هو الـ ID الصحيح للزر
    if (langBtn) {
        langBtn.click();
    }
''',
    '',
    'js: remove the forced language click',
)
sub(
    '''    if(open) setTimeout(()=>document.getElementById('wInput').focus(), 250);''',
    '''    if(open) setTimeout(()=>widget.querySelector('.w-foot a').focus(), 250);''',
    'js: focus the first contact action instead of the removed input',
)
sub(
    """    document.getElementById('wInput').placeholder = T[l].ph;\n""",
    '',
    'js: drop the placeholder assignment for the removed input',
)
sub(
    '''    renderMarq(l);
    cur = l;



  localStorage.setItem('lang', cur);
    u();
  }''',
    '''    renderMarq(l);
    cur = l;
    try { localStorage.setItem('lang', cur); } catch (e) { /* storage unavailable */ }
  }''',
    'js: persist the language choice; drop the u() call for the removed legal modals',
)

# --------------------------------------------------------------------------------------------------------
# 12. ENGLISH DICTIONARY — every key whose Arabic text changed needs its English sibling changed too, or the
#     language switch would restore the corrected claim in English.
# --------------------------------------------------------------------------------------------------------
sub(
    "    n1:'Channels', n2:'WhatsApp API', n3:'AI Assistant', n4:'Features', n5:'Reports', n6:'Security',",
    "    n1:'Channels', n2:'WhatsApp API', n3:'AI assist', n4:'Features', n5:'Reports', n6:'Security',\n"
    "    n7:'Docs',",
    'en: nav labels',
)
sub(
    "    cta1:'Try it free', cta2:'See supported channels',",
    "    cta1:'Create your account', cta2:'See supported channels',",
    'en: hero CTA',
)
sub(
    "    pr1:'channels, one inbox', pr2:'languages, live translation', pr3:'AI auto-replies',",
    "    pr1:'channels in one inbox', pr2:'languages in the agent interface', pr3:'and webhooks to connect your systems',",
    'en: hero proof points',
)
sub(
    "    wh1:'Welcome 👋', wh2:'Lynomia team is online — avg. reply: 2 min',",
    "    wh1:'Get in touch 👋', wh2:'Pick whichever suits you',\n"
    "    wb1:'Email us', wb2:'Documentation',",
    'en: contact card header and buttons',
)
sub(
    "    wm1:'Hi! This is the same widget that goes on your website — in your colors and your language.',\n"
    "    wm2:'Ask us anything about the platform, or request a demo for your team 🙌',",
    "    wm1:'Pre-sales questions: email us and we will reply.',\n"
    "    wm2:'Already a customer? Sign in and open a ticket from Help &amp; Support.',",
    'en: contact card body',
)

# --------------------------------------------------------------------------------------------------------
# 13. BRAND LOGO LINKS — both pointed at href="#", which scrolls nowhere and tells a crawler nothing. The
#     home page's own address is the correct destination for a masthead logo.
# --------------------------------------------------------------------------------------------------------
sub(
    '    <a class="brand" href="#" aria-label="Lynomia Chat">',
    '    <a class="brand" href="/" aria-label="Lynomia Chat">',
    'nav: brand logo -> /',
)
sub(
    '        <a class="brand" href="#">',
    '        <a class="brand" href="/">',
    'footer: brand logo -> /',
)

# --------------------------------------------------------------------------------------------------------
# 14. THE SECOND PASS. Correcting the Arabic DOM text is only half the job: every `data-i` key has an English
#     sibling in the EN dictionary, and switching language rewrites the DOM from it. A key corrected in Arabic
#     but not in English would restore the exact claim this hotfix removes, in English, on one click. The
#     browser check that follows this build switches languages and re-reads the page for that reason.
# --------------------------------------------------------------------------------------------------------

# 14a. The hero lede promised an AI that answers questions on its own — the same claim as the AI section.
sub(
    '      <p class="lead" data-i="lead">واتساب، إنستغرام، ماسنجر، تيليجرام، الإيميل وشات موقعك — كلها بلوحة واحدة لفريقك، مع ذكاء اصطناعي يردّ على الأسئلة المتكررة ويساعد وكلاءك يشتغلوا أسرع.</p>',
    '      <p class="lead" data-i="lead">واتساب، إنستغرام، ماسنجر، تيليجرام، الإيميل وشات موقعك — كلها بلوحة '
    'واحدة لفريقك، مع توزيع تلقائي للمحادثات، وقوالب ردود جاهزة، وتقارير تتابع أداء الفريق.</p>',
    'hero: lede -> capabilities that exist, instead of an AI that replies on its own',
)
sub(
    "    lead:'WhatsApp, Instagram, Messenger, Telegram, email and your website chat — all in one dashboard for your team, with AI that answers repetitive questions and helps your agents work faster.',",
    "    lead:'WhatsApp, Instagram, Messenger, Telegram, email and your website chat — all in one dashboard "
    "for your team, with automatic routing, ready-made reply templates and reports that track how your team "
    "is doing.',",
    'en: hero lede',
)

# 14b. The WhatsApp section claimed 24/7 AI auto-replies on WhatsApp.
sub(
    '<span data-i="wt4">ردود آلية على واتساب بالذكاء الاصطناعي 24/7</span>',
    '<span data-i="wt4">قواعد أتمتة وردود جاهزة ترسلها بضغطة واحدة</span>',
    'whatsapp: the 24/7 AI auto-reply tick -> automation rules and canned responses',
)
sub(
    "    wt4:'AI-powered auto-replies on WhatsApp, 24/7',",
    "    wt4:'Automation rules and canned responses, sent in one click',",
    'en: whatsapp tick',
)

# 14c. Invented performance statistics: "-60% of repeat tickets" and "3x faster average reply". Neither is
#      measured anywhere, and the owner's instruction forbids published performance percentages.
sub(
    '      <div class="ai-stat"><b>-60%</b><span data-i="as1">من حجم التذاكر المتكررة</span></div>\n'
    '      <div class="ai-stat"><b>3×</b><span data-i="as2">أسرع بمتوسط زمن الرد</span></div>\n'
    '      <div class="ai-stat"><b>50+</b><span data-i="as3">لغة مدعومة بالترجمة</span></div>\n',
    '      <div class="ai-stat"><b>5</b><span data-i="as1">أدوات مساعدة داخل المحادثة</span></div>\n'
    '      <div class="ai-stat"><b>OpenAI</b><span data-i="as2">بمفتاحك الخاص، تتحكم به وتوقفه متى شئت</span></div>\n'
    '      <div class="ai-stat"><b>0</b><span data-i="as3">رسائل تُرسل للعميل تلقائيًا</span></div>\n',
    'ai: invented statistics -> three facts about the assist',
)
sub(
    "    as1:'fewer repetitive tickets', as2:'faster average reply time', as3:'languages supported',",
    "    as1:'assist actions inside the conversation', as2:'with your own key, under your control',\n"
    "    as3:'messages sent to a customer automatically',",
    'en: ai statistics',
)

# 14d. The English half of every corrected AI string.
sub(
    "    aih2:'AI that replies for you… and backs your team when they reply themselves',",
    "    aih2:'Smart help for your agents — and they are the ones who press send',",
    'en: ai heading',
)
sub(
    "    ac1h:'Auto-replies 24/7',",
    "    ac1h:'Rewrite and summarise',",
    'en: ai card 1 heading',
)
sub(
    "    ac1p:'Answers repetitive questions instantly from your knowledge base — and hands the conversation to a human agent when it needs a human touch.',",
    "    ac1p:'Improve the wording of a reply before you send it, or condense a long conversation into a few "
    "lines before handing it over — the final text stays with your agent.',",
    'en: ai card 1 body',
)
sub(
    "    ac1q:'How do I change my password?',",
    "    ac1q:'Draft: \u201cWe cannot help you with this request.\u201d',",
    'en: ai card 1 demo question',
)
sub(
    "    ac1t:'Resolved automatically · no human needed',",
    "    ac1t:'Suggested to the agent · sent by hand',",
    'en: ai card 1 tag',
)
sub(
    "    ac3h:'Live translation · 50+ languages',",
    "    ac3h:'Message translation · needs setup',",
    'en: ai card 3 heading',
)
sub(
    "    ac3p:'The customer writes in their language, your agent reads and replies in theirs — translation happens in the background, invisible to both.',",
    "    ac3p:'Translate a single message on demand inside the conversation, once you connect your own Google "
    "Translate account. It is not on by default and does not translate whole conversations in the "
    "background. The agent interface itself is available in more than 50 languages.',",
    'en: ai card 3 body',
)

# 14e. The English half of the security section.
sub(
    "    sh2:'Enterprise-grade security — and your customer data stays yours',",
    "    sh2:'Complete isolation between accounts — and your customer data stays yours',",
    'en: security heading',
)
sub(
    "    sp:'Full encryption in transit and at rest, fine-grained permissions for every team member, and an audit log of every action — your customer conversations stay fully under your control.',",
    "    sp:'Encrypted transport over HTTPS with HSTS, channel credentials encrypted at rest, fine-grained "
    "permissions for every member, and an audit trail of configuration changes and sign-ins that the person "
    "being audited cannot switch off.',",
    'en: security lede',
)
sub(
    "    s1h:'Full encryption', s1p:'In transit and at rest, with daily backups.',",
    "    s1h:'Encrypted in transit', s1p:'HTTPS with HSTS, and channel and store credentials encrypted at rest.',",
    'en: security shield 1',
)
sub(
    "    s3h:'Audit log', s3p:'Every account action is recorded and traceable — for governance and compliance.',",
    "    s3h:'Audit trail', s3p:'Configuration changes and sign-ins are recorded, and kept for 365 days by default.',",
    'en: security shield 3',
)

# 14f. The English half of the closing call to action.
sub(
    "    ctap:'Get Lynomia Chat running for your team in one day — we connect your channels and WhatsApp API, set up auto-replies, and train your team on the dashboard.',",
    "    ctap:'Connect your channels into one inbox, route conversations to your team, and follow performance "
    "in the reports. The documentation is ready in Arabic and English, and our team helps you set up.',",
    'en: closing paragraph',
)
sub(
    "    ctab:'Talk to us now',",
    "    ctab:'Create your account',",
    'en: closing button',
)
sub(
    "    ctahint:'Free trial · no credit card · support in Arabic & English',",
    "    ctahint:'A question before you start? <a href=\"mailto:info@lynomia.com\" "
    "style=\"text-decoration:underline\">Email us</a> or read the <a href=\"/docs\" "
    "style=\"text-decoration:underline\">documentation</a>.',",
    'en: closing hint',
)
sub(
    "    fc3h:'Get in touch', flchat:'Live chat — we reply in minutes',",
    "    fc3h:'Get in touch', flchat:'Sign in to open a support ticket',",
    'en: footer support link',
)

# 14g. KEY COLLISION. The two footer entries added earlier reused `fl5` and `fl6`, which the English
#      dictionary already defines as "About us" and "Other services" — so one click on EN would have
#      relabelled the documentation and changelog links. Fresh keys instead.
sub(
    f'          <li><a href="{DOCS}" data-i="fl5">الوثائق ومركز المساعدة</a></li>\n'
    f'          <li><a href="{CHANGELOG}" data-i="fl6">سجل التحديثات</a></li>\n',
    f'          <li><a href="{DOCS}" data-i="fl9">الوثائق ومركز المساعدة</a></li>\n'
    f'          <li><a href="{CHANGELOG}" data-i="fl10">سجل التحديثات</a></li>\n',
    'footer: use unused i18n keys for the two new links',
)
sub(
    "    fc2h:'Lynomia', fl5:'About us', fl6:'Other services', fl7:'Blog', fl8:'Join our team',",
    "    fc2h:'Lynomia', fl5:'About us', fl6:'Other services', fl7:'Blog', fl8:'Join our team',\n"
    "    fl9:'Documentation &amp; help centre', fl10:'Changelog',",
    'en: labels for the two new footer links',
)
sub("fl3:'AI assistant'", "fl3:'AI assist'", 'en: footer product label')

def replace_line(text, prefix, new_line, note):
    """Replace a whole source line by its unique prefix.

    Used where the line contains a mix of real characters and literal backslash escapes (the EN dictionary
    stores `\\u2019` as text while the arrows beside it are real glyphs), which makes a literal anchor a
    quoting puzzle with no upside.
    """
    lines = text.split('\n')
    hits = [i for i, l in enumerate(lines) if l.startswith(prefix)]
    if len(hits) != 1:
        sys.exit(f'line replace matched {len(hits)} lines for {note}: {prefix!r}')
    lines[hits[0]] = new_line
    print(f' ok  {note}')
    return '\n'.join(lines)


def remove_legal_modal(text):
    """Remove the legal-modal machinery: its stylesheet, its markup, and the script that holds the policy
    text (F10).

    WHY THIS MUST GO AND NOT JUST THE LINKS. Replacing the four footer links with the operator's approved
    pages is not enough on its own: the modal is also opened from the URL hash by a DOMContentLoaded handler
    and a hashchange handler, so https://chat.lynomia.com/#privacy would still render the page's own
    hand-written policy text — including a "Last Updated" date and a Google API Limited-Use disclosure that
    nobody approved as the published policy. Two documents answering to one brand is the defect; the
    corrected page keeps exactly one, on the corporate domain.

    `let cur = 'ar';` is declared inside this script and is read by the second script (setLang, T[cur]), so
    the block is replaced by that one declaration rather than deleted outright.
    """
    removed = []

    style = re.search(r'\n[ \t]*<style>\n[ \t]*\.modal-overlay \{.*?</style>\n', text, re.S)
    if not style:
        sys.exit('structural: modal stylesheet not found')
    removed.append(('modal stylesheet', len(style.group(0))))
    text = text[:style.start()] + '\n' + text[style.end():]

    markup_start = text.find('<div id="modal-overlay"')
    if markup_start == -1:
        sys.exit('structural: modal markup not found')
    markup_end = text.find('</div>\n</div>\n', markup_start)
    if markup_end == -1:
        sys.exit('structural: modal markup end not found')
    markup_end += len('</div>\n</div>\n')
    removed.append(('modal markup', markup_end - markup_start))
    text = text[:markup_start] + text[markup_end:]

    script_start = text.find('<script>')
    script_end = text.find('</script>', script_start)
    if script_start == -1 or script_end == -1:
        sys.exit('structural: first script block not found')
    block = text[script_start:script_end + len('</script>')]
    for required in ("let cur = 'ar';", 'let contentData = {', 'function openModal(', 'function u()'):
        if required not in block:
            sys.exit(f'structural: the first script is not the legal-modal script (missing {required!r})')
    removed.append(('legal-content script', len(block)))
    text = text[:script_start] + (
        "<script>\n"
        "  /* The page is served in Arabic; `cur` tracks the language the visitor is currently reading.\n"
        "     The legal documents that used to live here as JavaScript string literals, rendered into a\n"
        "     modal, now have real URLs: see the footer. */\n"
        "  let cur = 'ar';\n"
        "</script>"
    ) + text[script_end + len('</script>'):]

    for what, size in removed:
        print(f' ok  structural: removed the {what} ({size:,} chars)')
    return text


src = io.open(SRC, encoding='utf-8').read()
actual_sha = hashlib.sha256(src.encode('utf-8')).hexdigest()
if actual_sha != SRC_SHA:
    sys.exit(f'snapshot sha256 mismatch: expected {SRC_SHA}, got {actual_sha}')

out = src
log = []
for old, new, note, count in edits:
    found = out.count(old)
    if found != count:
        sys.exit(f'EDIT NOT APPLICABLE ({found} of {count} matches): {note}\n  anchor: {old[:160]!r}')
    out = out.replace(old, new, count)
    log.append(f'{"ok":>3}  {note}')

print('\n'.join(log))
log = []
out = replace_line(
    out,
    "    aipp:'The AI agent learns",
    "    aipp:'Five assist tools inside the inbox: rewrite a reply, summarise a conversation, suggest a "
    "reply, suggest labels, and draft a follow-up. They switch on for your account when you connect your "
    "own OpenAI key, and nothing is ever sent to a customer without your agent approving it.',",
    'en: ai lede',
)
out = replace_line(
    out,
    "    ac1a:'Settings",
    "    ac1a:'After rewriting: \u201cThis request is outside what we can do today, and here is the "
    "alternative we suggest\u2026\u201d',",
    'en: ai card 1 demo answer',
)
out = remove_legal_modal(out)

# Guard rails: the corrected page must not contain any of the removed claims.
FORBIDDEN = [
    '99.98', 'daily 03:00', 'TLS 1.3 + AES-256', 'system status',
    'متوسط الرد: دقيقتين', 'تجربة مجانية', 'بدون بطاقة ائتمانية',
    'حُلّت آليًا', 'ردود آلية 24/7', 'كل إجراء بالحساب مسجّل', 'مكالمات صوتية', 'Voice calls',
    "langBtn.click()", 'sendW(',
    'openModal(', 'closeModal(', 'contentData', 'modal-overlay', 'Last Updated: July 15',
    'onclick="toggleWidget(true);return false"',
    'href="#"',
    # the English dictionary must not restore any corrected claim
    'Auto-replies 24/7', 'Resolved automatically', 'AI agent learns', 'Free trial', 'no credit card',
    'fewer repetitive tickets', 'faster average reply', 'Every account action is recorded',
    'Full encryption', 'daily backups', 'Live chat — we reply in minutes', 'AI that answers repetitive',
    'AI-powered auto-replies', '-60%',
]
for needle in FORBIDDEN:
    if needle in out:
        sys.exit(f'GUARD FAILED: removed claim still present: {needle!r}')

io.open(DST, 'w', encoding='utf-8').write(out)
(HERE / '_edits.txt').unlink(missing_ok=True)

print('\n'.join(log))
print(f'\n{len(edits)} edits applied')
print(f'in  {SRC.name}  {len(src.encode("utf-8")):,} bytes ({len(src):,} chars)')
print(f'out {DST.name}  {len(out.encode("utf-8")):,} bytes ({len(out):,} chars)')
print(f'    sha256 {hashlib.sha256(out.encode("utf-8")).hexdigest()}')
