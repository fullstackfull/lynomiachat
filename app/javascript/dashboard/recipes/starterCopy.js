// Curated Arabic and English copy for the flow templates (docs/usability/11-flow-templates.md §copy). Written by hand,
// never machine-translated, and editable in the builder before anything is published.
//
// `body`   message text. "Both" sends the Arabic line and the English line in one message.
// `title`  a button or list option's visible title, which WhatsApp limits to 20 characters (24 in a list), so the
//          bilingual form is its own short wording rather than two titles joined.

export const LANGUAGES = ['ar', 'en', 'both'];

/**
 * A message body in the chosen language.
 * @param {string} language - 'ar', 'en' or 'both'.
 * @param {Object} pair - `{ ar, en }`.
 * @returns {string} The text to send.
 */
export const body = (language, pair) => {
  if (language === 'ar') return pair.ar;
  if (language === 'en') return pair.en;
  return `${pair.ar}\n${pair.en}`;
};

/**
 * An option title in the chosen language, short enough for WhatsApp.
 * @param {string} language - 'ar', 'en' or 'both'.
 * @param {Object} pair - `{ ar, en, both }`.
 * @returns {string} The title to show.
 */
export const title = (language, pair) => {
  if (language === 'en') return pair.en;
  if (language === 'ar') return pair.ar;
  return pair.both;
};

export const COPY = {
  // Shared wording several templates use.
  CONNECTING: {
    ar: 'شكرًا لك. سنوصلك بأحد أفراد الفريق الآن.',
    en: 'Thank you. We are connecting you to someone from the team now.',
  },
  TEAM_WILL_REPLY: {
    ar: 'شكرًا لك! سيرد عليك أحد أفراد الفريق هنا قريبًا.',
    en: 'Thank you! Someone from the team will reply here shortly.',
  },

  WELCOME: {
    ASK: {
      ar: 'مرحبًا! 👋 أخبرنا باختصار بما تحتاجه، وسنوصلك بالشخص المناسب.',
      en: 'Hello! 👋 Tell us briefly what you need, and we will connect you to the right person.',
    },
    NOTE: 'Started by the welcome flow. The customer’s request is the message above.',
  },

  TRACKING: {
    MENU: {
      ar: 'مرحبًا! 👋 كيف يمكننا مساعدتك؟',
      en: 'Hello! 👋 How can we help you?',
    },
    TRACK: {
      ar: 'تتبع طلبي',
      en: 'Track my order',
      both: 'تتبع الطلب / Track',
    },
    TEAM: {
      ar: 'التحدث مع الفريق',
      en: 'Talk to the team',
      both: 'الفريق / Team',
    },
    LATEST: {
      ar: 'طلبك الأحدث هو #{{flow.order.number}}، وحالته الحالية: {{flow.order.status}}.',
      en: 'Your most recent order is #{{flow.order.number}}, and its current status is {{flow.order.status}}.',
    },
    ANYTHING_ELSE: {
      ar: 'هل يمكننا مساعدتك في شيء آخر؟',
      en: 'Can we help you with anything else?',
    },
    DONE: { ar: 'هذا كل شيء', en: "That's all", both: 'تم / Done' },
    ASK_NUMBER: {
      ar: 'لم نجد طلبًا حديثًا على هذا الرقم. أرسل لنا رقم الطلب وسنتحقق منه.',
      en: 'We could not find a recent order for this number. Send us the order number and we will check it.',
    },
    FOUND: {
      ar: 'الطلب #{{flow.order.number}} حالته: {{flow.order.status}}.',
      en: 'Order #{{flow.order.number}} is {{flow.order.status}}.',
    },
    NOT_FOUND: {
      ar: 'لم نتمكن من العثور على هذا الرقم. سنوصلك بالفريق للمتابعة.',
      en: 'We could not find that number. We are connecting you to the team.',
    },
    BYE: {
      ar: 'شكرًا لتواصلك معنا. نحن هنا وقتما تحتاجنا.',
      en: 'Thank you for contacting us. We are here whenever you need us.',
    },
    NOTE: 'Started by the order tracking flow.',
  },

  ROUTING: {
    MENU: {
      ar: 'مرحبًا! 👋 اختر الموضوع وسنوصلك بالفريق المناسب.',
      en: 'Hello! 👋 Choose a topic and we will connect you to the right team.',
    },
    ORDERS: { ar: 'الطلبات', en: 'Orders', both: 'الطلبات / Orders' },
    PRODUCTS: { ar: 'المنتجات', en: 'Products', both: 'المنتجات / Products' },
    OTHER: { ar: 'شيء آخر', en: 'Something else', both: 'شيء آخر / Other' },
    ACK_ORDERS: {
      ar: 'شكرًا لك. سنوصلك بفريق الطلبات.',
      en: 'Thank you. We are connecting you to our orders team.',
    },
    ACK_PRODUCTS: {
      ar: 'شكرًا لك. سنوصلك بفريق المنتجات.',
      en: 'Thank you. We are connecting you to our products team.',
    },
    NOTE_ORDERS: 'Routing flow: the customer chose Orders.',
    NOTE_PRODUCTS: 'Routing flow: the customer chose Products.',
    NOTE_OTHER: 'Routing flow: the customer chose Something else.',
  },

  VIP: {
    ACK: {
      ar: 'أهلًا بك 🌟 سنوصلك بفريقنا المخصص على الفور.',
      en: 'Welcome 🌟 We are connecting you to our dedicated team right away.',
    },
    NOTE: 'VIP flow: the contact is in the chosen shared audience.',
    STANDARD_NOTE:
      'VIP flow: the contact is not in the chosen shared audience.',
  },

  BILINGUAL: {
    CHOOSE: {
      ar: 'اختر لغتك المفضلة',
      en: 'Choose your language',
    },
    ARABIC: { ar: 'العربية', en: 'العربية', both: 'العربية' },
    ENGLISH: { ar: 'English', en: 'English', both: 'English' },
    ACK_AR: {
      ar: 'تم، سنتابع معك بالعربية. سيرد عليك أحد أفراد الفريق قريبًا.',
      en: 'تم، سنتابع معك بالعربية. سيرد عليك أحد أفراد الفريق قريبًا.',
    },
    ACK_EN: {
      ar: 'Great, we will continue in English. Someone from the team will reply shortly.',
      en: 'Great, we will continue in English. Someone from the team will reply shortly.',
    },
    NOTE_AR: 'Bilingual flow: the customer chose Arabic.',
    NOTE_EN: 'Bilingual flow: the customer chose English.',
  },

  AFTER_SALES: {
    ASK_NUMBER: {
      ar: 'مرحبًا! 👋 أرسل لنا رقم الطلب الذي تحتاج المساعدة فيه.',
      en: 'Hello! 👋 Send us the number of the order you need help with.',
    },
    FOUND: {
      ar: 'شكرًا لك، وجدنا الطلب #{{flow.order.number}}.',
      en: 'Thank you, we found order #{{flow.order.number}}.',
    },
    WHICH_ISSUE: {
      ar: 'ما المشكلة التي تواجهها؟',
      en: 'What is the problem?',
    },
    WRONG: { ar: 'صنف خاطئ', en: 'Wrong item', both: 'صنف خاطئ / Wrong' },
    DAMAGED: { ar: 'تالف', en: 'Damaged', both: 'تالف / Damaged' },
    LATE: { ar: 'تأخر التوصيل', en: 'Late delivery', both: 'تأخر / Late' },
    NOT_FOUND: {
      ar: 'لم نتمكن من العثور على هذا الرقم، وسنساعدك على أي حال.',
      en: 'We could not find that number, and we will help you anyway.',
    },
    NOTE_WRONG: 'Order issue: wrong item.',
    NOTE_DAMAGED: 'Order issue: damaged.',
    NOTE_LATE: 'Order issue: late delivery.',
    NOTE_UNKNOWN: 'Order issue: the order number could not be found.',
  },
};
