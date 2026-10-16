# The approved content enhancements, as content.
#
# READ BY `Marketing::PageEnrichment`, which `instance_eval`s this file and expects an array of
# `Enrichment`. It lives here rather than inside that module so the copy can be reviewed as copy -- the
# mechanism is one file, the words are another.
#
# EVERY SCREENSHOT NAMED HERE IS A REAL CAPTURE of the running dashboard against the seeded `acme.inc` demo
# account, taken at the revision this branch is cut from. There is no mock-up, no illustration of a
# dashboard and no stock image in this file. `docs/screenshots/README.md` is the contract they come under.
#
# THE ARABIC PAGE GETS THE ARABIC DASHBOARD. `sources/marketing/ar/*` were captured with the account's
# locale set to `ar`, so the Arabic page shows a right-to-left interface with Arabic labels. Putting the
# English screenshot on the Arabic page would be showing a reader an interface they will not be given.
#
# NO CLAIM HERE EXCEEDS WHAT THE PICTURE SHOWS. The copy describes the screen beside it; the figures that
# would need evidence (counts, percentages, uptime) are not in this file at all.

whatsapp_strip = {
  'en' => { heading: 'The apps your customers already message you on',
            lede: 'Connect the ones you need. Every conversation lands in the same inbox.' },
  'ar' => { heading: 'التطبيقات التي يراسلك عليها عملاؤك فعلاً',
            lede: 'وصّل ما تحتاجه. وكل محادثة تصل إلى الصندوق نفسه.' }
}

flow_copy = {
  'en' => { heading: 'Six places your customers write from. One place your team works in.',
            lede: 'Every message arrives in the same list, with its history attached, whichever app it came from.',
            outbox_label: 'Lynomia Chat', inbox_label: 'One shared inbox' },
  'ar' => { heading: 'ستة أماكن يكتب منها عملاؤك. ومكان واحد يعمل فيه فريقك.',
            lede: 'كل رسالة تصل إلى القائمة نفسها، ومعها سجلها، من أي تطبيق جاءت.',
            outbox_label: 'لينوميا شات', inbox_label: 'صندوق وارد واحد مشترك' }
}

showcases = {
  'inbox' => {
    file: 'conversation-open.png', after: 'flow', position: 'top',
    'en' => {
      kicker: 'The agent workspace',
      heading: 'Read it, answer it, and see who the customer is — on one screen',
      lede: 'This is the screen your team spends the day in, photographed from the running product.',
      alt: 'The Lynomia Chat agent workspace: the channel list, a conversation open in the middle, and the customer panel beside it.',
      link_label: 'What the inbox does', link_target: 'page:feature:unified_inbox',
      items: [
        ['Every channel in one list', 'WhatsApp, Instagram, Messenger, email, website chat and SMS arrive in the same queue, each row saying who wrote and which channel it came from.'],
        ['The customer beside the reply', 'Their details, earlier conversations, private notes and labels sit next to the message you are writing, not in a second tab.'],
        ['One owner, not a committee', 'Give a conversation to a person or a team and mark how urgent it is.']
      ]
    },
    'ar' => {
      kicker: 'مساحة عمل وكيل الدعم',
      heading: 'اقرأها، وأجب عليها، واعرف من العميل — في شاشة واحدة',
      lede: 'هذه هي الشاشة التي يقضي فيها فريقك يومه، مُصوَّرة من المنتج وهو يعمل.',
      alt: 'مساحة عمل وكيل الدعم في لينوميا شات: قائمة القنوات، ومحادثة مفتوحة في الوسط، ولوحة العميل بجانبها.',
      link_label: 'ماذا يفعل الصندوق الموحّد', link_target: 'page:feature:unified_inbox',
      items: [
        ['كل القنوات في قائمة واحدة', 'واتساب وإنستغرام وماسنجر والبريد ودردشة الموقع والرسائل النصية تصل إلى الطابور نفسه، ويقول كل صف من كتب ومن أي قناة.'],
        ['العميل بجانب الرد', 'بياناته ومحادثاته السابقة وملاحظاتك الخاصة ووسومه بجوار الرسالة التي تكتبها، لا في تبويب ثانٍ.'],
        ['مالك واحد، لا لجنة', 'أعطِ المحادثة لشخص أو لفريق وحدّد مدى إلحاحها.']
      ]
    }
  },
  'automation' => {
    file: 'automation-editor.png', after: 'showcase', position: 'end',
    'en' => {
      kicker: 'Automation',
      heading: 'Say what should happen, without writing code',
      lede: 'A rule reads an event, checks the conditions you set, and takes the actions you chose.',
      alt: 'The Lynomia Chat automation rule editor, showing an event, its conditions and the actions it runs.',
      link_label: 'How automation rules work', link_target: 'page:feature:automation',
      items: [
        ['Trigger', 'A conversation is created, updated, resolved, or a message comes in.'],
        ['Conditions', 'Narrow it by channel, label, team, priority, country or a custom attribute.'],
        ['Actions', 'Assign, label, change priority, send a reply or a private note, or call a webhook.']
      ]
    },
    'ar' => {
      kicker: 'الأتمتة',
      heading: 'قل ما ينبغي أن يحدث، دون كتابة شيفرة',
      lede: 'القاعدة تقرأ الحدث، وتتحقق من الشروط التي ضبطتها، وتنفّذ الإجراءات التي اخترتها.',
      alt: 'محرر قواعد الأتمتة في لينوميا شات، ويظهر فيه الحدث وشروطه والإجراءات التي ينفّذها.',
      link_label: 'كيف تعمل قواعد الأتمتة', link_target: 'page:feature:automation',
      items: [
        ['المُطلِق', 'إنشاء محادثة، أو تحديثها، أو حلّها، أو وصول رسالة.'],
        ['الشروط', 'ضيّقها بالقناة أو الوسم أو الفريق أو الأولوية أو الدولة أو سمة مخصصة.'],
        ['الإجراءات', 'الإسناد، أو الوسم، أو تغيير الأولوية، أو إرسال رد أو ملاحظة خاصة، أو استدعاء ويب هوك.']
      ]
    }
  },
  'analytics' => {
    file: 'reports.png', after: 'showcase', position: 'start',
    'en' => {
      kicker: 'Reporting',
      heading: 'See how the team is actually doing',
      lede: 'Conversation volume, response and resolution times, and how the load is spread across agents and teams.',
      alt: 'The Lynomia Chat reports screen, showing conversation metrics over a selected date range.',
      link_label: 'What the reports cover', link_target: 'page:feature:analytics',
      items: [
        ['Filter and compare', 'By date range, inbox, team, agent or label.'],
        ['Per agent and per team', 'Who is carrying what, and where the queue is slowest.'],
        ['Customer satisfaction', 'CSAT responses alongside the conversations they came from.']
      ]
    },
    'ar' => {
      kicker: 'التقارير',
      heading: 'اعرف كيف يسير أداء الفريق فعلاً',
      lede: 'حجم المحادثات، وأزمنة الرد والحل، وكيف يتوزّع الحمل على وكلاء الدعم والفرق.',
      alt: 'شاشة التقارير في لينوميا شات، وتظهر فيها مؤشرات المحادثات خلال مدى زمني محدد.',
      link_label: 'ماذا تغطّي التقارير', link_target: 'page:feature:analytics',
      items: [
        ['رشّح وقارن', 'بالمدى الزمني أو القناة أو الفريق أو وكيل الدعم أو الوسم.'],
        ['لكل وكيل ولكل فريق', 'من يحمل ماذا، وأين يبطؤ الطابور.'],
        ['رضا العملاء', 'ردود قياس الرضا بجانب المحادثات التي جاءت منها.']
      ]
    }
  }
}

# THE WHATSAPP BAND. The product's headline draw is the official WhatsApp Business API and the homepage had
# it as one row of a ten-row text index. The four points are the ones
# docs/official-website/02-verified-feature-inventory.md:34-37, 245, 249 actually supports -- Cloud API with
# your own credentials or Embedded Signup, a template manager, template campaigns behind their flag, and the
# same inbox as every other channel. Nothing here claims a reply bot, a delivery guarantee or an uptime
# figure.
whatsapp_band = {
  'en' => {
    kicker: 'WhatsApp Business API',
    heading: 'The official WhatsApp Business API, not a phone on a desk',
    lede: 'Connect your business number through the official Cloud API. Your customers message the number ' \
          'they already have, and every message lands in the same inbox as the rest.',
    note: 'The preview is the shape of an approved template: an image header, a body carrying your ' \
          'variables, a footer and up to ten quick-reply buttons.',
    link_label: 'How WhatsApp works here', link_target: 'page:channel:whatsapp',
    items: [
      'The official Cloud API — your own credentials, or connect through Meta in the browser',
      'Build message templates, submit them and watch their approval without leaving the dashboard',
      'Send an approved template to a saved audience as a campaign, with delivery reported per recipient',
      'Replies arrive in the shared inbox beside every other channel, with the contact attached'
    ]
  },
  'ar' => {
    kicker: 'واجهة واتساب للأعمال',
    heading: 'واجهة واتساب الرسمية للأعمال، لا هاتف على المكتب',
    lede: 'اربط رقم شركتك عبر واجهة واتساب السحابية الرسمية. يراسلك عملاؤك على الرقم الذي يعرفونه، وتصل كل ' \
          'رسالة إلى الصندوق نفسه مع بقية القنوات.',
    note: 'المعاينة هي شكل قالب معتمد: ترويسة بصورة، ونص يحمل متغيّراتك، وتذييل، وحتى عشرة أزرار رد سريع.',
    link_label: 'كيف يعمل واتساب هنا', link_target: 'page:channel:whatsapp',
    items: [
      'الواجهة السحابية الرسمية — ببياناتك أنت، أو بالربط عبر ميتا من المتصفح',
      'أنشئ قوالب الرسائل وأرسلها للاعتماد وتابع حالتها دون مغادرة لوحة التحكم',
      'أرسل قالبًا معتمدًا إلى جمهور محفوظ كحملة، مع تقرير تسليم لكل مستلم',
      'الردود تصل إلى الصندوق المشترك بجانب كل قناة أخرى، ومعها بطاقة جهة الاتصال'
    ]
  }
}

# THE ASSIST BAND, written against docs/official-website/02-verified-feature-inventory.md:129-130 -- the one
# sentence that programme concluded may honestly be said about AI here: five agent-assist actions, available
# when the account connects its own OpenAI key, and nothing sent to a customer without an agent pressing
# send. `note` carries that gate inside the band rather than in a footnote.
assist_band = {
  'en' => {
    kicker: 'Assistance for your agents',
    heading: 'Help your team write — they still press send',
    lede: 'Five actions inside the composer: rewrite a reply, summarise a long thread, suggest a reply, ' \
          'suggest labels, and refine a follow-up.',
    note: 'Off until your account connects its own OpenAI key. Nothing is ever sent to a customer ' \
          'automatically.',
    link_label: 'What the assist actions do', link_target: 'page:feature:ai_assist',
    items: [
      ['Rewrite a reply', 'cant refund it, policy is 14 days',
       'I am sorry — our returns window is 14 days, so I cannot refund this order. Here is what I can do.'],
      ['Summarise a thread', 'Thirty-one messages across four days',
       'Charged twice on 3 March. Refund approved; waiting on the payment provider.'],
      ['Suggest labels', 'A new conversation, nothing on it yet', 'billing · refund · urgent']
    ]
  },
  'ar' => {
    kicker: 'مساعدة لوكلاء الدعم',
    heading: 'ساعد فريقك على الكتابة — ويبقى الإرسال بيده',
    lede: 'خمسة إجراءات داخل صندوق الرد: إعادة صياغة الرد، وتلخيص محادثة طويلة، واقتراح رد، واقتراح وسوم، ' \
          'وصياغة رسالة متابعة.',
    note: 'معطّلة حتى يربط حسابك مفتاح OpenAI الخاص به. ولا تُرسَل أي رسالة إلى عميل تلقائيًا.',
    link_label: 'ماذا تفعل إجراءات المساعدة', link_target: 'page:feature:ai_assist',
    items: [
      ['إعادة صياغة الرد', 'ما ينفع نرجّع المبلغ، السياسة ١٤ يوم',
       'آسف — مدة الإرجاع لدينا أربعة عشر يومًا، ولذلك لا أستطيع استرجاع قيمة هذا الطلب. وهذا ما يمكنني فعله.'],
      ['تلخيص المحادثة', 'إحدى وثلاثون رسالة على مدى أربعة أيام',
       'خُصم المبلغ مرتين في ٣ مارس. ووُفِق على الاسترجاع، وبانتظار مزوّد الدفع.'],
      ['اقتراح الوسوم', 'محادثة جديدة لا وسم عليها بعد', 'الفوترة · استرجاع · عاجل']
    ]
  }
}

HERO_ALT = {
  'en' => 'The Lynomia Chat agent workspace: the channel list on one side, a customer conversation open in the middle, and the contact panel beside it.',
  'ar' => 'مساحة عمل وكيل الدعم في لينوميا شات: قائمة القنوات في جانب، ومحادثة عميل مفتوحة في الوسط، ولوحة جهة الاتصال بجانبها.'
}.freeze

enrichments = []

%w[en ar].each do |locale|
  enrichments << Enrichment.new(
    key: "home.channel-strip.#{locale}", locale: locale, slug: 'home', after: 'hero',
    section: { 'type' => 'channel_strip' }.merge(whatsapp_strip[locale].transform_keys(&:to_s))
  )

  enrichments << Enrichment.new(
    key: "home.flow.#{locale}", locale: locale, slug: 'home', after: 'stats',
    section: { 'type' => 'flow' }.merge(flow_copy[locale].transform_keys(&:to_s))
  )

  showcases.each do |name, spec|
    copy = spec[locale]
    enrichments << Enrichment.new(
      key: "home.showcase.#{name}.#{locale}", locale: locale, slug: 'home', after: spec[:after],
      image: { file: "docs/screenshots/sources/marketing/#{locale}/#{spec[:file]}", field: 'attachment_id' },
      section: {
        'type' => 'showcase',
        'kicker' => copy[:kicker], 'heading' => copy[:heading], 'lede' => copy[:lede],
        'alt' => copy[:alt], 'media_position' => spec[:position],
        'link_label' => copy[:link_label], 'link_target' => copy[:link_target],
        'items' => copy[:items].map { |title, body| { 'title' => title, 'body' => body } }
      }
    )
  end
end

%w[en ar].each do |locale|
  # THE TWO BANDS THE OLD SITE HAD AND THIS ONE DID NOT. `after` names a TYPE, and `position_for` takes the
  # LAST section of that type, so the WhatsApp band lands below all three showcases and the assist band below
  # the WhatsApp band -- whatever order an operator has put the showcases in.
  copy = whatsapp_band[locale]
  enrichments << Enrichment.new(
    key: "home.whatsapp.#{locale}", locale: locale, slug: 'home', after: 'showcase',
    section: {
      'type' => 'device',
      'kicker' => copy[:kicker], 'heading' => copy[:heading], 'lede' => copy[:lede], 'note' => copy[:note],
      'link_label' => copy[:link_label], 'link_target' => copy[:link_target],
      'items' => copy[:items].map { |title| { 'title' => title } }
    }
  )

  copy = assist_band[locale]
  enrichments << Enrichment.new(
    key: "home.assist.#{locale}", locale: locale, slug: 'home', after: 'device',
    section: {
      'type' => 'before_after',
      'kicker' => copy[:kicker], 'heading' => copy[:heading], 'lede' => copy[:lede], 'note' => copy[:note],
      'link_label' => copy[:link_label], 'link_target' => copy[:link_target],
      'items' => copy[:items].map do |title, before, after|
        { 'title' => title, 'before' => before, 'after' => after }
      end
    }
  )
end

%w[en ar].each do |locale|
  # THE HERO'S SCREENSHOT IS A FILL, NOT AN INSERT: every page already has a hero, and what it needed was a
  # picture of the product in place of the hand-built panel the template used to draw. It is written only
  # when the hero carries no image, so an operator who has chosen their own keeps it.
  enrichments << Enrichment.new(
    key: "home.hero-shot.#{locale}", locale: locale, slug: 'home',
    fill: { type: 'hero' },
    image: { file: "docs/screenshots/sources/marketing/#{locale}/conversation-open.png", field: 'attachment_id' },
    section: { 'alt' => HERO_ALT[locale] }
  )
end

enrichments
