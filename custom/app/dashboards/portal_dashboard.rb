# frozen_string_literal: true

require 'administrate/base_dashboard'

# Lynomia global documentation: the two platform portals. They are seeded rather than created here -- their slugs are
# what /docs and /changelog resolve, and what the contextual-help registry builds its links from -- so Super Admin
# edits their presentation and leaves their identity alone.
class PortalDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String.with_options(searchable: true),
    slug: Field::String,
    page_title: Field::String,
    header_text: Field::Text,
    color: Field::String,
    custom_domain: Field::String,
    homepage_link: Field::String,
    archived: Field::Boolean,
    config: SerializedField,
    categories: CountField,
    articles: CountField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name slug categories articles updated_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    id name slug page_title header_text color custom_domain homepage_link archived config categories articles
    created_at updated_at
  ].freeze
  FORM_ATTRIBUTES = %i[name page_title header_text color custom_domain homepage_link archived].freeze

  def display_resource(portal)
    portal.name
  end

  def self.resource_name(opts = {})
    opts[:count].to_i == 1 ? 'Documentation site' : 'Documentation sites'
  end
end
