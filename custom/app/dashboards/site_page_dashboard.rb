# frozen_string_literal: true

require 'administrate/base_dashboard'

# One page of the official website, as the operator edits it.
#
# THE SOURCE-OF-TRUTH BOUNDARY IS THIS LIST OF FORM ATTRIBUTES. The row owns the page's words -- its title,
# description, heading, standfirst, sections and SEO -- and nothing else. A feature's availability state, its
# prerequisite, which catalogue it belongs to and which pages are related to it come from
# Marketing::Catalog, carried beside the evidence in docs/official-website/02-verified-feature-inventory.md,
# and none of them appears on this form. An operator editing a conditional capability into an available one is
# the exact failure this rebuild exists to remove, so the editor cannot express it.
#
# `locale`, `kind` AND `key` ARE THE IDENTITY and are editable only on create. The public controller looks a
# page up by the identity the route handed it, so changing one on an existing row would silently detach the
# page from its URL and from its translation sibling. `slug` is editable on a detail page, which is what
# SiteRedirect exists to cover, and is pinned to the key on a standing page by the model.
class SitePageDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    locale: Field::Select.with_options(collection: MarketingHelper::LOCALES),
    kind: Field::Select.with_options(collection: SitePage::KINDS),
    key: Field::String.with_options(searchable: true),
    slug: Field::String.with_options(searchable: true),
    status: Field::Select.with_options(collection: SitePage.statuses.keys),
    position: Field::Number,
    title: Field::String.with_options(searchable: true),
    description: Field::Text.with_options(searchable: true),
    heading: Field::String.with_options(searchable: true),
    lede: Field::Text,
    sections: SitePageSectionsField,
    meta: SitePageMetaField,
    published_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id locale kind key status position title sections].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id locale kind key slug status position title description heading lede sections meta
    published_at created_at updated_at
  ].freeze

  # Content and SEO, never identity: this is the EDIT form, and `locale`, `kind` and `key` are deliberately
  # absent from it.
  FORM_ATTRIBUTES = %i[slug position title description heading lede sections meta].freeze

  # The identity is settable once, on create. `FORM_ATTRIBUTES_NEW` is Administrate's own per-action override
  # (base_dashboard.rb:57-70, which maps `create` to `new`), so no controller or dashboard method is needed to
  # make the two forms differ.
  FORM_ATTRIBUTES_NEW = %i[
    locale kind key slug position title description heading lede sections meta
  ].freeze

  COLLECTION_FILTERS = {
    drafts: ->(resources) { resources.where(status: :draft) },
    arabic: ->(resources) { resources.where(locale: 'ar') },
    english: ->(resources) { resources.where(locale: 'en') }
  }.freeze

  def display_resource(page)
    "#{page.locale} · #{page.kind}/#{page.key}"
  end
end
