# THE DEMO SHOP'S OWN WORDS, IN THE READER'S LANGUAGE.
#
# The widget translates its own chrome from the visitor's browser language: "We are online", the reply-time
# estimate, Start Conversation, the Lynomia Chat byline. The WELCOME HEADING, the TAGLINE and the GREETING
# are not chrome. They are three fields an operator types into the channel, stored once and sent to every
# visitor exactly as written, whatever language that visitor reads in.
#
# So the Arabic figure captured against the English channel came out as an Arabic widget with an English
# heading in it, the tagline's full stop stranded on the wrong end of the line -- a picture of a shop that
# has not finished setting its widget up, published under a caption saying this is what the visitor sees.
# An Arabic operator's widget says these three things in Arabic, so the Arabic figure is taken against a
# channel that does.
#
# Both sets live here, rather than in the fixture and again in the capture, so the two cannot drift.
#
#   bundle exec rails runner 'require "./tools/visual/widget_copy"
#     WidgetCopy.apply!(Account.first.inboxes.find_by!(channel_type: "Channel::WebWidget"), "ar")'
module WidgetCopy
  # PaperLayer is a stationery shop that does not exist (`tools/visual/widget-host/index.html`). The navy is
  # the colour its own page uses, which is the point -- the widget takes the colour of the site it sits on.
  COLOR = '#1B2338'.freeze

  COPY = {
    'en' => {
      welcome_title: 'Talk to PaperLayer',
      welcome_tagline: 'Questions about an order, a delivery or a product? Start a conversation and ' \
                       'someone from the shop will answer.',
      greeting: 'Thanks for getting in touch. Tell us what you need and we will pick it up from here.'
    },
    'ar' => {
      welcome_title: 'تحدّث إلى PaperLayer',
      welcome_tagline: 'سؤال عن طلب أو شحنة أو منتج؟ ابدأ محادثة وسيردّ عليك أحد موظفي المتجر.',
      greeting: 'شكراً لتواصلك معنا. أخبرنا بما تحتاجه ونكمل من هنا.'
    }
  }.freeze

  def self.apply!(inbox, locale)
    words = COPY.fetch(locale)
    inbox.channel.update!(
      widget_color: COLOR,
      welcome_title: words[:welcome_title],
      welcome_tagline: words[:welcome_tagline],
      reply_time: :in_a_few_minutes
    )
    inbox.update!(greeting_enabled: true, greeting_message: words[:greeting])
  end
end
