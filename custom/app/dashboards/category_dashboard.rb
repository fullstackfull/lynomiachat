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

  # There is no `FORM_ATTRIBUTES_EDIT`, because there is no edit action: `config/routes/documentation.rb`
  # declares `resources :categories, except: [:edit, :update]`. The constant that used to live here held
  # `locale` out of the edit form -- the other half of the seeder's `(slug, locale)` lookup -- and it is now
  # dead, because the whole surface is gone rather than one field.
  #
  # FORM_ATTRIBUTES therefore serves `new`/`create` only, where every field IS the operator's to choose: a
  # hand-made section has no manifest row, so the seeder neither authors nor overwrites it.

  def display_resource(category)
    "#{category.name} (#{category.locale})"
  end

  def self.resource_name(opts = {})
    opts[:count].to_i == 1 ? 'Documentation section' : 'Documentation sections'
  end
end
