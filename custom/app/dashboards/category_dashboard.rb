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
  # THERE IS NO `FORM_ATTRIBUTES`, and no `FORM_ATTRIBUTES_EDIT` either, because this dashboard has no form:
  # `config/routes/documentation.rb` declares `resources :categories, only: [:index, :show, :destroy]`.
  # `manifest.yml` is the sole author of a section's `name`, `description`, `position` and `icon`, and `slug`
  # and `locale` are the two halves of the key `Documentation::ContentSeeder#upsert_category` looks a section
  # up by -- `find_or_initialize_by(slug:, locale:)`
  # (custom/app/services/documentation/content_seeder.rb:384). Renaming a slug here would make the next seed
  # create a SECOND category at the manifest slug while every article stayed on the renamed one, and 404 a
  # previously indexed URL (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D4).
  #
  # Nothing in Administrate reads these constants outside a form: `form_attributes` is reached only from
  # `Administrate::Page::Form` (administrate-0.20.1/lib/administrate/page/form.rb:14) and from
  # `permitted_attributes`, which the controller calls only for `create` and `update`
  # (administrate-0.20.1/app/controllers/administrate/application_controller.rb:204-206). `index`, `show` and
  # `destroy` read COLLECTION_ATTRIBUTES and SHOW_PAGE_ATTRIBUTES, below, so every field stays visible and
  # searchable while none is writable.

  def display_resource(category)
    "#{category.name} (#{category.locale})"
  end

  def self.resource_name(opts = {})
    opts[:count].to_i == 1 ? 'Documentation section' : 'Documentation sections'
  end
end
