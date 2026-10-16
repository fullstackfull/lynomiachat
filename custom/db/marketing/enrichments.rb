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
            outbox_label: 'لنوميا شات', inbox_label: 'صندوق وارد واحد مشترك' }
}

showcases = {
  'inbox' => {
    :file => 'figures/conversation-list.png', :after => 'flow', :position => 'top',
    'en' => {
      kicker: 'The agent workspace',
      heading: 'Read it, answer it, and see who the customer is — on one screen',
      lede: 'This is the screen your team spends the day in, photographed from the running product.',
      alt: 'The Lynomia Chat conversation list: the channels down the side, and a queue whose rows each say ' \
           'who wrote and which channel the message arrived on.',
      link_label: 'What the inbox does', link_target: 'page:feature:unified_inbox',
      items: [
        ['Every channel in one list',
         'WhatsApp, Instagram, Messenger, email, website chat and SMS arrive in the same queue, each ' \
         'row saying who wrote and which channel it came from.'],
        ['The customer beside the reply',
         'Their details, earlier conversations, private notes and labels sit next to the message you are writing, not in a second tab.'],
        ['One owner, not a committee', 'Give a conversation to a person or a team and mark how urgent it is.']
      ]
    },
    'ar' => {
      kicker: 'مساحة عمل وكيل الدعم',
      heading: 'اقرأها، وأجب عليها، واعرف من العميل — في شاشة واحدة',
      lede: 'هذه هي الشاشة التي يقضي فيها فريقك يومه، مُصوَّرة من المنتج وهو يعمل.',
      alt: 'قائمة المحادثات في لنوميا شات: القنوات على الجانب، وطابور يقول كل صفّ فيه من كتب ومن أي قناة ' \
           'وصلت الرسالة.',
      link_label: 'ماذا يفعل الصندوق الموحّد', link_target: 'page:feature:unified_inbox',
      items: [
        ['كل القنوات في قائمة واحدة',
         'واتساب وإنستغرام وماسنجر والبريد ودردشة الموقع والرسائل النصية تصل إلى الطابور نفسه، ويقول كل صف من كتب ومن أي قناة.'],
        ['العميل بجانب الرد', 'بياناته ومحادثاته السابقة وملاحظاتك الخاصة ووسومه بجوار الرسالة التي تكتبها، لا في تبويب ثانٍ.'],
        ['مالك واحد، لا لجنة', 'أعطِ المحادثة لشخص أو لفريق وحدّد مدى إلحاحها.']
      ]
    }
  },
  'automation' => {
    :file => 'figures/automation-rule.png', :after => 'showcase', :position => 'end',
    'en' => {
      kicker: 'Automation',
      heading: 'Say what should happen, without writing code',
      lede: 'A rule reads an event, checks the conditions you set, and takes the actions you chose.',
      alt: 'The Add Automation Rule dialog in Lynomia Chat: the event that starts a rule, a condition row ' \
           'and an action row, each waiting for the value to apply it to.',
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
      alt: 'نافذة إضافة قاعدة أتمتة في لنوميا شات: الحدث الذي يبدأ القاعدة، وصفّ شرط وصفّ إجراء، ' \
           'وكلٌّ منهما ينتظر القيمة التي يُطبَّق عليها.',
      link_label: 'كيف تعمل قواعد الأتمتة', link_target: 'page:feature:automation',
      items: [
        ['المُطلِق', 'إنشاء محادثة، أو تحديثها، أو حلّها، أو وصول رسالة.'],
        ['الشروط', 'ضيّقها بالقناة أو الوسم أو الفريق أو الأولوية أو الدولة أو سمة مخصصة.'],
        ['الإجراءات', 'الإسناد، أو الوسم، أو تغيير الأولوية، أو إرسال رد أو ملاحظة خاصة، أو استدعاء ويب هوك.']
      ]
    }
  },
  'analytics' => {
    :file => 'figures/reports-overview.png', :after => 'showcase', :position => 'start',
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
      alt: 'شاشة التقارير في لنوميا شات، وتظهر فيها مؤشرات المحادثات خلال مدى زمني محدد.',
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

# A LOCAL, NOT A CONSTANT. This file is `instance_eval`ed, so a constant here is defined on Module and
# Ruby warns "already initialized constant" the second time the declarations are loaded -- which a spec does
# on every example that reloads them.
hero_alt = {
  'en' => 'The Lynomia Chat agent workspace: the channel list on one side, a customer conversation open ' \
          'in the middle, and the contact panel beside it.',
  'ar' => 'مساحة عمل وكيل الدعم في لنوميا شات: قائمة القنوات في جانب، ومحادثة عميل مفتوحة في الوسط، ولوحة جهة الاتصال بجانبها.'
}

# THE SECTION SKELETONS, hoisted out of the loop. A frozen literal rebuilt on every pass is the same object
# every time, and `merge` returns a new hash anyway -- so building them here costs nothing and keeps the
# loop reading as "one page's worth of content" rather than as hash construction.
strip_skeleton = { 'type' => 'channel_strip' }.freeze
flow_skeleton = { 'type' => 'flow' }.freeze

enrichments = []

# ONE PASS PER LOCALE, IN THE ORDER THE SECTIONS LAND. `after` names a TYPE and `position_for` takes the
# LAST section of that type, so the order inside this block is what puts the WhatsApp band below all three
# showcases and the assist band below the WhatsApp band -- whatever order an operator has put them in.
%w[en ar].each do |locale|
  enrichments << Enrichment.new(
    key: "home.channel-strip.#{locale}", locale: locale, slug: 'home', after: 'hero',
    section: strip_skeleton.merge(whatsapp_strip[locale].transform_keys(&:to_s))
  )

  enrichments << Enrichment.new(
    key: "home.flow.#{locale}", locale: locale, slug: 'home', after: 'stats',
    section: flow_skeleton.merge(flow_copy[locale].transform_keys(&:to_s))
  )

  showcases.each do |name, spec|
    copy = spec[locale]
    enrichments << Enrichment.new(
      key: "home.showcase.#{name}.#{locale}", locale: locale, slug: 'home', after: spec[:after],
      # A `figures/` PREFIX MEANS A CROP, not the whole screen. `docs/screenshots/figures.json` says what
      # each one is a crop of and why; `node tools/visual/crop.mjs` regenerates them and `--check` fails if
      # one is stale.
      #
      # THE INBOX SHOWCASE TOOK THE WHOLE CAPTURE UNTIL THE HOMEPAGE WAS LOOKED AT AS A PAGE. `home.hero-shot`
      # names the same file, `PageEnrichment.resolve_image` matches an existing attachment by basename, so both
      # ended up holding ONE attachment id and the homepage published the identical 1440x900 screenshot twice.
      # The showcase now takes a crop of the half the hero is not about -- the channel sidebar and the list.
      image: { file: if spec[:file].start_with?('figures/')
                       "docs/screenshots/figures/marketing/#{locale}/#{spec[:file].delete_prefix('figures/')}"
                     else
                       "docs/screenshots/sources/marketing/#{locale}/#{spec[:file]}"
                     end,
               field: 'attachment_id' },
      section: {
        'type' => 'showcase',
        'kicker' => copy[:kicker], 'heading' => copy[:heading], 'lede' => copy[:lede],
        'alt' => copy[:alt], 'media_position' => spec[:position],
        'link_label' => copy[:link_label], 'link_target' => copy[:link_target],
        'items' => copy[:items].map { |title, body| { 'title' => title, 'body' => body } }
      }
    )
  end

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

  # THE HERO'S SCREENSHOT IS A FILL, NOT AN INSERT: every page already has a hero, and what it needed was a
  # picture of the product in place of the hand-built panel the template used to draw. It is written only
  # when the hero carries no image, so an operator who has chosen their own keeps it. It takes the untouched
  # capture rather than a crop, for the reason the inbox showcase does.
  enrichments << Enrichment.new(
    key: "home.hero-shot.#{locale}", locale: locale, slug: 'home',
    fill: { type: 'hero' },
    image: { file: "docs/screenshots/sources/marketing/#{locale}/conversation-open.png",
             field: 'attachment_id' },
    section: { 'alt' => hero_alt[locale] }
  )
end

# ---------------------------------------------------------------------------------------------------------
# THE DETAIL PAGES GET THE SAME TREATMENT AS THE HOMEPAGE: a real screenshot and a way into the manual.
#
# Eight pages carried the product's claims entirely in prose. Each one now opens, under its hero, on a
# picture of the screen it is about and a link to the article that explains how to work it. The link is a
# ROOT-RELATIVE PATH to the documentation (`/docs/<slug>`, and `-ar` for the Arabic article), which is what
# `Marketing::LinkTarget` allows and what survives a marketing-page rename.
#
# WHY THESE EIGHT. They are the pages where a reader has already decided they are interested and wants to
# know what the thing looks like and how it works. A page whose subject this project has no honest
# screenshot of is not in this list.
detail_showcases = {
  'unified-inbox' => {
    :file => ->(locale) { "docs/screenshots/sources/marketing/#{locale}/conversation-open.png" },
    :docs => 'work-in-the-inbox',
    'en' => {
      kicker: 'One inbox', heading: 'Every channel, in one list',
      lede: 'WhatsApp, website chat, email, Telegram and the rest arrive in the same place, in the order ' \
            'they came, with the customer attached.',
      alt: 'The Lynomia Chat conversation list beside an open conversation and its reply box.',
      link_label: 'How to work in the inbox',
      items: [['One list', 'Filter by channel, assignment, status, label or priority.'],
              ['One history', 'Every conversation with a contact, on any channel, in one place.'],
              ['One reply box', 'The same composer whatever the channel, with saved replies behind a slash.']]
    },
    'ar' => {
      kicker: 'صندوق واحد', heading: 'كل القنوات في قائمة واحدة',
      lede: 'واتساب ودردشة الموقع والبريد وتيليجرام وغيرها تصل إلى المكان نفسه، بترتيب وصولها، ومعها العميل.',
      alt: 'قائمة المحادثات في لنوميا شات إلى جوار محادثة مفتوحة وصندوق الرد.',
      link_label: 'كيف تعمل في صندوق الوارد',
      items: [['قائمة واحدة', 'رشّح بالقناة أو الإسناد أو الحالة أو التصنيف أو الأولوية.'],
              ['سجل واحد', 'كل محادثات جهة الاتصال، على أي قناة، في مكان واحد.'],
              ['صندوق رد واحد', 'المحرّر نفسه مهما كانت القناة، والردود المحفوظة خلف شَرطة مائلة.']]
    }
  },
  'live-chat' => {
    :file => ->(locale) { "docs/screenshots/sources/widget/#{locale}/host-open.png" },
    :docs => 'website-live-chat',
    'en' => {
      kicker: 'Website chat', heading: 'A chat bubble on your own site, in your own colour',
      lede: 'One script tag. The visitor clicks, types, and the message lands in the inbox your team ' \
            'already works in.',
      alt: 'A shop page with the Lynomia Chat widget open in the corner, showing its welcome heading and ' \
           'a Start Conversation button.',
      link_label: 'Set up website chat',
      items: [['Your words', 'The heading, the tagline and the reply time are yours to write.'],
              ['Your brand', 'The bubble takes the colour of the site it sits on.'],
              ['Your domains', 'Restrict the widget to the sites you own.']]
    },
    'ar' => {
      kicker: 'دردشة الموقع', heading: 'فقاعة دردشة على موقعك أنت، بلونك أنت',
      lede: 'وسم برمجي واحد. ينقر الزائر، ويكتب، فتهبط الرسالة في الصندوق الذي يعمل فيه فريقك أصلاً.',
      alt: 'صفحة متجر وأداة لنوميا شات مفتوحة في الزاوية، وفيها العنوان الترحيبي وزر "ابدأ المحادثة".',
      link_label: 'جهّز دردشة الموقع',
      items: [['كلماتك', 'العنوان والافتتاحية ووقت الرد كلها تكتبها أنت.'],
              ['هويتك', 'الفقاعة تأخذ لون الموقع الذي تجلس عليه.'],
              ['نطاقاتك', 'اقصر الأداة على المواقع التي تملكها.']]
    }
  },
  'automation' => {
    :file => ->(locale) { "docs/screenshots/figures/marketing/#{locale}/automation-rule.png" },
    :docs => 'automation-rules',
    'en' => {
      kicker: 'Automation', heading: 'Say what should happen, without writing code',
      lede: 'An event, some conditions, and the actions to take. The rule dialog is the whole of it.',
      alt: 'The automation rule dialog: the event that starts it, and the rows where a condition and an ' \
           'action are built, their values not yet chosen.',
      link_label: 'How automation rules work',
      items: [['On arrival', 'Label, assign, reply or escalate the moment a message lands.'],
              ['On a delay', 'Re-check the conditions when the clock runs out, and act only if they still hold.'],
              ['On a change', 'React when a conversation is resolved, reopened or updated.']]
    },
    'ar' => {
      kicker: 'الأتمتة', heading: 'قل ما ينبغي أن يحدث، دون كتابة شيفرة',
      lede: 'حدث، وبعض الشروط، والإجراءات التي تُتخذ. ونافذة القاعدة هي كل الأمر.',
      alt: 'نافذة قاعدة الأتمتة: الحدث الذي يبدؤها، والصفوف التي يُبنى فيها الشرط والإجراء، وقيمها لم تُختر بعد.',
      link_label: 'كيف تعمل قواعد الأتمتة',
      items: [['عند الوصول', 'صنّف أو أسند أو ردّ أو صعّد لحظة هبوط الرسالة.'],
              ['بعد تأجيل', 'أعد فحص الشروط حين تنتهي الساعة، ولا تتصرّف إلا إن بقيت قائمة.'],
              ['عند تغيّر', 'تفاعل حين تُحلّ المحادثة أو يُعاد فتحها أو تُحدَّث.']]
    }
  },
  'analytics' => {
    :file => ->(locale) { "docs/screenshots/figures/marketing/#{locale}/reports-overview.png" },
    :docs => 'reports',
    'en' => {
      kicker: 'Reports', heading: 'How the team is actually doing',
      lede: 'Volume, response times and resolutions, by agent, channel, label and team — with the records ' \
            'behind every bar.',
      alt: 'The reports overview: live counters for open, unattended and unassigned work, and a week of ' \
           'conversation traffic by day and hour.',
      link_label: 'What each report answers',
      items: [['Live', 'Open, unattended, unassigned and pending, counted now.'],
              ['Over time', 'First response and resolution times, with business hours on or off.'],
              ['Drill down', 'Click a bar to read the conversations it is made of.']]
    },
    'ar' => {
      kicker: 'التقارير', heading: 'كيف حال الفريق فعلاً',
      lede: 'الحجم وأزمنة الرد والحلول، بحسب الوكيل والقناة والتصنيف والفريق — ومعها السجلات خلف كل عمود.',
      alt: 'نظرة التقارير العامة: عدّادات حيّة للعمل المفتوح وغير المتابَع وغير المُسنَد، وأسبوع من حركة ' \
           'المحادثات بحسب اليوم والساعة.',
      link_label: 'عمَّ يجيب كل تقرير',
      items: [['الآن', 'المفتوح وغير المتابَع وغير المُسنَد والمعلّق، معدوداً هذه اللحظة.'],
              ['عبر الزمن', 'أزمنة أول ردّ والحل، بساعات العمل أو بدونها.'],
              ['تعمّق', 'انقر عموداً لتقرأ المحادثات التي يتكوّن منها.']]
    }
  },
  'campaigns' => {
    :file => ->(locale) { "docs/screenshots/sources/marketing/#{locale}/campaigns-whatsapp.png" },
    :docs => 'whatsapp-campaigns',
    'en' => {
      kicker: 'Campaigns', heading: 'Reach a group on purpose, and see what happened',
      lede: 'Pick an audience, pick an approved template, send — then read who received it and who did not.',
      alt: 'The WhatsApp campaigns list, with each campaign, its audience and its status.',
      link_label: 'How WhatsApp campaigns work',
      items: [['An audience', 'Built from labels and contact attributes, saved and reused.'],
              ['A template', 'Only an approved template leaves the 24-hour window.'],
              ['An outcome', 'Addressed, sent, delivered, read, failed and skipped, per campaign.']]
    },
    'ar' => {
      kicker: 'الحملات', heading: 'اختر مجموعة وأرسل إليها عن قصد، وانظر ماذا حدث',
      lede: 'اختر جمهوراً، واختر قالباً معتمداً، وأرسل — ثم اقرأ من استلم ومن لم يستلم.',
      alt: 'قائمة حملات واتساب، وفيها كل حملة وجمهورها وحالتها.',
      link_label: 'كيف تعمل حملات واتساب',
      items: [['جمهور', 'مبنيّ من التصنيفات وسمات جهات الاتصال، محفوظ ومُعاد استخدامه.'],
              ['قالب', 'لا يخرج من نافذة الـ٢٤ ساعة إلا قالب معتمد.'],
              ['نتيجة', 'المخاطَب والمُرسل والمُسلَّم والمقروء والفاشل والمتخطّى، لكل حملة.']]
    }
  },
  'contact-management' => {
    :file => ->(locale) { "docs/screenshots/sources/marketing/#{locale}/contacts.png" },
    :docs => 'contacts',
    'en' => {
      kicker: 'Contacts', heading: 'Who they are, not just what they last said',
      lede: 'Every message creates or finds a contact, so the person is the record and the channel is a ' \
            'detail.',
      alt: 'The contacts list, with names, channels, labels and the attributes held against each person.',
      link_label: 'Working with contacts',
      items: [['One person, many channels', 'The same customer on WhatsApp and email is one contact.'],
              ['Your own fields', 'Custom attributes for the things your business needs to know.'],
              ['Import and export', 'Bring a list in as a CSV, and take it out again.']]
    },
    'ar' => {
      kicker: 'جهات الاتصال', heading: 'من هم، لا آخر ما قالوه فقط',
      lede: 'كل رسالة تُنشئ جهة اتصال أو تجدها، فالشخص هو السجل والقناة تفصيل.',
      alt: 'قائمة جهات الاتصال، وفيها الأسماء والقنوات والتصنيفات والسمات المحفوظة لكل شخص.',
      link_label: 'العمل مع جهات الاتصال',
      items: [['شخص واحد، قنوات كثيرة', 'العميل نفسه على واتساب والبريد جهة اتصال واحدة.'],
              ['حقولك أنت', 'سمات مخصّصة لما يحتاج عملك معرفته.'],
              ['استيراد وتصدير', 'أدخل قائمة بصيغة CSV، وأخرجها مرة أخرى.']]
    }
  },
  'support-desk' => {
    :file => ->(locale) { "docs/screenshots/sources/app/#{locale}/support-cases.png" },
    :docs => 'support-cases',
    'en' => {
      kicker: 'Support cases', heading: 'For the work that outlives the conversation',
      lede: 'A refund waiting on finance, a bug waiting on a developer: a case with an owner, a due time ' \
            'and a history you can read back.',
      alt: 'The support case list, with references, subjects, statuses, priorities, owners and SLA states.',
      link_label: 'How support cases work',
      items: [['An owner', 'One person, or a team, and a status that says who is blocked.'],
              ['A due time', 'An SLA policy with first-response and resolution targets.'],
              ['A history', 'Every change, who made it, and when.']]
    },
    'ar' => {
      kicker: 'حالات الدعم', heading: 'للعمل الذي يعيش بعد المحادثة',
      lede: 'استرداد ينتظر المالية، وعطب ينتظر مطوّراً: حالة لها مالك ووقت استحقاق وسجلّ يمكن قراءته لاحقاً.',
      alt: 'قائمة حالات الدعم، وفيها المراجع والمواضيع والحالات والأولويات والمالكون وحالات اتفاقية الخدمة.',
      link_label: 'كيف تعمل حالات الدعم',
      items: [['مالك', 'شخص واحد أو فريق، وحالة تقول من المحجوب.'],
              ['وقت استحقاق', 'سياسة اتفاقية خدمة بأهداف لأول ردّ وللحل.'],
              ['سجلّ', 'كل تغيير، ومن أجراه، ومتى.']]
    }
  },
  'team-collaboration' => {
    :file => ->(locale) { "docs/screenshots/sources/marketing/#{locale}/conversation-assignment.png" },
    :docs => 'teams-and-agents',
    'en' => {
      kicker: 'Teams', heading: 'One owner per conversation, and everyone can see who',
      lede: 'Assign to a person or a team, set a priority, and leave a private note nobody outside sees.',
      alt: 'A conversation with its side panel open on the assigned agent, the assigned team and the priority.',
      link_label: 'Teams, agents and permissions',
      items: [['An assignee', 'Handed out in turn, or picked up by hand.'],
              ['A team', 'The group that owns the question, with its own view.'],
              ['A private note', 'Said to each other, inside the conversation, never to the customer.']]
    },
    'ar' => {
      kicker: 'الفرق', heading: 'مالك واحد لكل محادثة، والجميع يرى من هو',
      lede: 'أسنِد إلى شخص أو فريق، وحدّد أولوية، واترك ملحوظة خاصة لا يراها أحد من الخارج.',
      alt: 'محادثة ولوحتها الجانبية مفتوحة على الوكيل المكلف والفريق المكلف والأولوية.',
      link_label: 'الفرق والوكلاء والصلاحيات',
      items: [['مُسنَد إليه', 'يُوزَّع بالدور، أو يُلتقط باليد.'],
              ['فريق', 'المجموعة التي تملك السؤال، ولها عرضها الخاص.'],
              ['ملحوظة خاصة', 'تُقال بينكم داخل المحادثة، ولا تصل العميل أبداً.']]
    }
  }
}

%w[en ar].each do |locale|
  detail_showcases.each do |slug, spec|
    copy = spec[locale]
    enrichments << Enrichment.new(
      # NO `after:`, WHICH PUTS IT FIRST. `after` names a type to sit behind, and a detail page has no
      # `hero` section to name: its heading and standfirst are chrome that `_page.html.erb` draws in a
      # `<header>`, and `Marketing::ContentBlueprint#detail_page` builds the body as `cards` plus an
      # optional `note`. `PageEnrichment#position_for` appends when the named type is absent, so
      # `after: 'hero'` -- which this read until the band was looked at on a rendered page -- put the
      # screenshot at the BOTTOM, under the bullet cards, which is the one place it does not belong.
      # `after: nil` returns 0, and the band opens the page the way the copy above says it does.
      key: "detail.showcase.#{slug}.#{locale}", locale: locale, slug: slug,
      image: { file: spec[:file].call(locale), field: 'attachment_id' },
      section: {
        'type' => 'showcase',
        'kicker' => copy[:kicker], 'heading' => copy[:heading], 'lede' => copy[:lede],
        'alt' => copy[:alt], 'media_position' => 'top',
        'link_label' => copy[:link_label],
        # The ARTICLE, not another marketing page: a reader on a feature page who wants more wants the
        # manual. Arabic articles carry an `-ar` slug (Documentation::ContentSeeder keeps one globally
        # unique slug per article), so the link follows the reader's language.
        'link_target' => "/docs/#{spec[:docs]}#{locale == 'ar' ? '-ar' : ''}",
        'items' => copy[:items].map { |title, body| { 'title' => title, 'body' => body } }
      }
    )
  end
end

enrichments
