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
    file: 'conversation-open.png', after: 'flow', position: 'start',
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

enrichments
