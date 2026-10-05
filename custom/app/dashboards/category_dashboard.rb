# frozen_string_literal: true

require 'administrate/base_dashboard'

# Lynomia global documentation: the sections of the documentation and changelog portals. A category is per locale, so
# the English and Arabic versions of one section are two rows sharing a slug (Category validates locale uniqueness
# within slug and portal).
class CategoryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    portal: Field::BelongsTo.with_options(scope: -> { Documentation::Library.portals }),
    name: Field::String.with_options(searchable: true),
    slug: Field::String.with_options(searchable: true),
    description: Field::Text,
    locale: Field::Select.with_options(collection: Documentation::Library::LOCALES),
    position: Field::Number,
    icon: Field::String,
    articles: CountField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name portal locale slug position articles].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id name slug portal locale description position icon articles created_at updated_at].freeze
  FORM_ATTRIBUTES = %i[portal name slug description locale position icon].freeze

  def display_resource(category)
    "#{category.name} (#{category.locale})"
  end

  def self.resource_name(opts = {})
    opts[:count].to_i == 1 ? 'Documentation section' : 'Documentation sections'
  end
end
