# frozen_string_literal: true

require 'administrate/base_dashboard'

# The questions on /faq, as rows rather than as a blob.
#
# STRUCTURED ROWS ARE WHAT MAKES THE FAQPage STRUCTURED DATA HONEST: W5 generates it from the same question
# and the same answer the reader sees, and structured data that does not match the visible page breaks
# Google's own rule as well as being a lie. A single rich-text blob would let the two drift.
#
# THE ANSWER IS A PLAIN TEXT AREA, not an editor. The one piece of markup an answer needs is a link, and that
# is three validated fields here rather than syntax an operator has to remember -- the reasoning
# Marketing::SectionSchema sets out, including that this repository has already shipped a stored XSS through
# a Markdown path.
class SiteFaqEntryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    locale: Field::Select.with_options(collection: MarketingHelper::LOCALES),
    question: Field::Text.with_options(searchable: true),
    answer: Field::Text.with_options(searchable: true),
    link_label: Field::String,
    link_page_kind: Field::Select.with_options(collection: SitePage::KINDS, include_blank: true),
    link_page_key: Field::String,
    position: Field::Number,
    visible: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id locale position question visible].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id locale position question answer link_label link_page_kind link_page_key visible created_at updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    locale position question answer link_label link_page_kind link_page_key visible
  ].freeze

  COLLECTION_FILTERS = {
    hidden: ->(resources) { resources.where(visible: false) }
  }.freeze

  def display_resource(entry)
    entry.question.to_s.truncate(60)
  end
end
