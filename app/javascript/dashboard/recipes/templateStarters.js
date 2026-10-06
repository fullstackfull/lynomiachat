// Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/01-meta-api-contract.md): starting points for a
// template, kept in source like the other starters in this folder. They are not a library, not a marketplace, and not
// anything WhatsApp has seen: choosing one fills the builder with a draft to edit, and WhatsApp still reviews it like
// any other. Updating a starter here never touches a template somebody already made.
//
// Only the ones worth having are here. Deliberately absent: abandoned cart (no send context resolves a cart URL),
// promotional discounts (marketing copy a business has to write itself), one-time passcodes (WhatsApp writes an
// authentication template's text and needs an Android signature), satisfaction surveys (CSAT owns that template), and
// anything built from a catalogue, carousel or list component, which Lynomia Chat cannot send.
//
// Each starter carries its own text per template language, because a template's language is the customer's, not the
// dashboard's. `en_US` is the fallback when a starter has nothing in the chosen language.
export const TEMPLATE_STARTERS = [
  {
    id: 'order_shipped',
    name: 'order_shipped',
    category: 'UTILITY',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-truck',
    content: {
      en_US: {
        header: { format: 'TEXT', text: 'Your order is on its way' },
        body: 'Hi {{1}}, your order {{2}} has been shipped and should arrive in {{3}} working days.',
        footer: 'Reply to this message if anything looks wrong',
        examples: ['Dana', 'LY-2041', '3'],
        buttons: [
          {
            type: 'URL',
            text: 'Track order',
            url: 'https://example.com/track/{{1}}',
            example: 'LY-2041',
          },
        ],
      },
      ar: {
        header: { format: 'TEXT', text: 'طلبك في الطريق' },
        body: 'مرحباً {{1}}، تم شحن طلبك {{2}} ويصلك خلال {{3}} أيام عمل.',
        footer: 'ردّ على هذه الرسالة إن كان هناك أي خطأ',
        examples: ['دانة', 'LY-2041', '٣'],
        buttons: [
          {
            type: 'URL',
            text: 'تتبّع الطلب',
            url: 'https://example.com/track/{{1}}',
            example: 'LY-2041',
          },
        ],
      },
    },
  },
  {
    id: 'order_delivered',
    name: 'order_delivered',
    category: 'UTILITY',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-package-check',
    content: {
      en_US: {
        body: 'Hi {{1}}, order {{2}} was delivered today. Tell us if anything is missing and we will sort it out.',
        examples: ['Dana', 'LY-2041'],
        buttons: [
          { type: 'QUICK_REPLY', text: 'Everything is fine' },
          { type: 'QUICK_REPLY', text: 'I have a problem' },
        ],
      },
      ar: {
        body: 'مرحباً {{1}}، تم تسليم الطلب {{2}} اليوم. أخبرنا إن كان هناك نقص وسنعالجه.',
        examples: ['دانة', 'LY-2041'],
        buttons: [
          { type: 'QUICK_REPLY', text: 'كل شيء تمام' },
          { type: 'QUICK_REPLY', text: 'عندي مشكلة' },
        ],
      },
    },
  },
  {
    id: 'delivery_delayed',
    name: 'delivery_delayed',
    category: 'UTILITY',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-clock-alert',
    content: {
      en_US: {
        body: 'Hi {{1}}, order {{2}} is running late and we now expect it on {{3}}. Sorry for the wait.',
        examples: ['Dana', 'LY-2041', 'Thursday'],
      },
      ar: {
        body: 'مرحباً {{1}}، تأخر الطلب {{2}} ونتوقع وصوله {{3}}. نعتذر عن الانتظار.',
        examples: ['دانة', 'LY-2041', 'الخميس'],
      },
    },
  },
  {
    id: 'appointment_reminder',
    name: 'appointment_reminder',
    category: 'UTILITY',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-calendar-clock',
    content: {
      en_US: {
        body: 'Hi {{1}}, this is a reminder of your appointment on {{2}} at {{3}}.',
        examples: ['Dana', 'Monday', '4pm'],
        buttons: [
          { type: 'QUICK_REPLY', text: 'Confirm' },
          { type: 'QUICK_REPLY', text: 'Reschedule' },
        ],
      },
      ar: {
        body: 'مرحباً {{1}}، تذكير بموعدك يوم {{2}} الساعة {{3}}.',
        examples: ['دانة', 'الاثنين', '٤ عصراً'],
        buttons: [
          { type: 'QUICK_REPLY', text: 'تأكيد' },
          { type: 'QUICK_REPLY', text: 'تغيير الموعد' },
        ],
      },
    },
  },
  {
    id: 'payment_due',
    name: 'payment_due',
    category: 'UTILITY',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-receipt',
    content: {
      en_US: {
        body: 'Hi {{1}}, invoice {{2}} for {{3}} is due on {{4}}.',
        examples: ['Dana', 'INV-114', 'KD 24.500', 'Sunday'],
        buttons: [
          {
            type: 'URL',
            text: 'View invoice',
            url: 'https://example.com/invoice/{{1}}',
            example: 'INV-114',
          },
        ],
      },
      ar: {
        body: 'مرحباً {{1}}، الفاتورة {{2}} بمبلغ {{3}} مستحقة في {{4}}.',
        examples: ['دانة', 'INV-114', '٢٤.٥٠٠ د.ك', 'الأحد'],
        buttons: [
          {
            type: 'URL',
            text: 'عرض الفاتورة',
            url: 'https://example.com/invoice/{{1}}',
            example: 'INV-114',
          },
        ],
      },
    },
  },
  {
    id: 'back_in_stock',
    name: 'back_in_stock',
    category: 'MARKETING',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-package-plus',
    content: {
      en_US: {
        body: 'Good news {{1}} — {{2}} is back in stock.',
        footer: 'Reply STOP to unsubscribe',
        examples: ['Dana', 'the oud gift set'],
      },
      ar: {
        body: 'خبر سار {{1}} — توفر {{2}} من جديد.',
        footer: 'أرسل STOP لإلغاء الاشتراك',
        examples: ['دانة', 'طقم العود'],
      },
    },
  },
  {
    id: 'support_follow_up',
    name: 'support_follow_up',
    category: 'UTILITY',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-life-buoy',
    content: {
      en_US: {
        body: 'Hi {{1}}, we are still looking into your request {{2}} and will come back to you today.',
        examples: ['Dana', '#3391'],
      },
      ar: {
        body: 'مرحباً {{1}}، ما زلنا نتابع طلبك {{2}} وسنعود إليك اليوم.',
        examples: ['دانة', '#3391'],
      },
    },
  },
  {
    id: 'welcome_message',
    name: 'welcome_message',
    category: 'UTILITY',
    parameterFormat: 'POSITIONAL',
    icon: 'i-lucide-hand',
    content: {
      en_US: {
        body: 'Hi {{1}}, thanks for getting in touch with {{2}}. How can we help?',
        examples: ['Dana', 'Lynomia'],
      },
      ar: {
        body: 'مرحباً {{1}}، شكراً لتواصلك مع {{2}}. كيف نقدر نساعدك؟',
        examples: ['دانة', 'Lynomia'],
      },
    },
  },
];

// The starter's content for a template language, falling back to English when it has nothing in that one.
export const starterContent = (starter, language) =>
  starter.content[language] ||
  starter.content[String(language).split('_')[0]] ||
  starter.content.en_US;
