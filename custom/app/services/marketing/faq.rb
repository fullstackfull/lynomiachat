# The questions the site answers directly, and where each one leads.
#
# EVERY ANSWER IS A SHORT FORM OF A PAGE THAT ALREADY EXISTS, which is why each entry carries a link rather
# than a longer answer. An FAQ that restates a feature page is the duplicate-thin-content pattern search
# engines discount and readers resent; an FAQ that answers in two sentences and points at the page is the one
# worth having.
#
# THE QUESTIONS ARE THE ONES THE OLD SITE ANSWERED WRONGLY OR NOT AT ALL. "Do you have an AI chatbot", "how
# much does it cost", "is there a free trial" and "do you have certifications" are here because the honest
# answer to each is a no or a qualification, and a site that hides those questions is answering them anyway.
#
# `link` is either a Symbol naming a standing page or a [scope, entry_id] pair naming a catalogue page. W4
# moves the copy to operator-editable SiteFaqEntry rows; the link graph stays here, beside the code it
# resolves against.
module Marketing::Faq
  Entry = Struct.new(:id, :link, keyword_init: true)

  ENTRIES = [
    Entry.new(id: :channels, link: :channels),
    Entry.new(id: :ai, link: [:features, :ai_assist]),
    Entry.new(id: :price, link: :pricing),
    Entry.new(id: :trial, link: :pricing),
    Entry.new(id: :own_number, link: [:channels, :whatsapp]),
    Entry.new(id: :arabic, link: :home),
    Entry.new(id: :orders, link: [:features, :commerce]),
    Entry.new(id: :isolation, link: [:features, :security]),
    Entry.new(id: :certifications, link: [:features, :security]),
    Entry.new(id: :api, link: [:features, :api_webhooks]),
    Entry.new(id: :support, link: :support),
    Entry.new(id: :export, link: [:features, :analytics])
  ].freeze

  def self.entries = ENTRIES
end
