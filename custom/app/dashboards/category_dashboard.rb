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
  # `slug` is deliberately absent, for the same reason it is absent from ArticleDashboard: it is the section's
  # public address and it is the key the seeder looks a section up by --
  # Documentation::ContentSeeder#upsert_category does `find_or_initialize_by(slug:, locale:)`
  # (custom/app/services/documentation/content_seeder.rb:98). Renaming it here makes the next seed create a
  # SECOND category at the manifest slug while every article stays on the renamed one, and 404s a previously
  # indexed URL (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D4). It stays on SHOW_PAGE_ATTRIBUTES and
  # stays searchable.
  FORM_ATTRIBUTES = %i[portal name description locale position icon].freeze

  # `locale` is the OTHER half of the key the seeder looks a section up by, and removing `slug` closed only one
  # half. Measured on a single-locale section: one form save flips the locale, the next seed creates a SECOND
  # section at the manifest locale, reattaches the articles to it, and leaves an orphan section published at the
  # other locale's URL that no manifest row authored and no run reports. Today's data is not exposed because
  # every shipped section exists in both locales, so `validates :locale, uniqueness: { scope: [:slug,
  # :portal_id] }` refuses the flip -- latent until a single-locale section exists.
  #
  # So locale is settable at creation (a hand-made section has to choose a language) and immutable afterwards,
  # which is class D. The EDIT constant alone closes BOTH the form and the write, because
  # `Administrate::BaseDashboard#form_attributes` rewrites the action before looking the constant up --
  # `when "update" then "edit"` (administrate-0.20.1/lib/administrate/base_dashboard.rb:53-60) -- and strong
  # params go through the same method (`application_controller.rb:204-206`). A `FORM_ATTRIBUTES_UPDATE` would
  # never be consulted.
  FORM_ATTRIBUTES_EDIT = %i[portal name description position icon].freeze

  def display_resource(category)
    "#{category.name} (#{category.locale})"
  end

  def self.resource_name(opts = {})
    opts[:count].to_i == 1 ? 'Documentation section' : 'Documentation sections'
  end
end
