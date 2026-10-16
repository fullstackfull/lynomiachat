# frozen_string_literal: true

require 'administrate/base_dashboard'

# The header and footer of the official website, as rows an operator owns.
#
# WHAT W2 SHIPPED AND THIS REPLACES: a hard-coded navigation in the layout. The point of making it rows is
# that an internal link is stored as a page REFERENCE (`page:feature:unified_inbox`) rather than a URL, so a
# renamed slug moves the link with it -- which a stored URL cannot do, and a managed navigation quietly
# filling up with 404s is worse than a hard-coded one.
#
# `target` AND `resolves` ARE SHOWN, NEVER EDITED. `target` is what the model builds from whichever of the two
# link columns is set, and `resolves` answers the only question an operator really has about a nav row: will
# this actually appear? The navigation drops a link whose page is unpublished or gone
# (MarketingHelper#marketing_nav), so a row that looks saved and never renders is otherwise invisible.
class SiteNavLinkDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    locale: Field::Select.with_options(collection: MarketingHelper::LOCALES),
    placement: Field::Select.with_options(collection: SiteNavLink::PLACEMENTS),
    label: Field::String.with_options(searchable: true),
    page_kind: Field::Select.with_options(collection: SitePage::KINDS, include_blank: true),
    page_key: Field::String.with_options(searchable: true),
    href: Field::String.with_options(searchable: true),
    position: Field::Number,
    visible: Field::Boolean,
    target: Field::String,
    resolves: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id locale placement position label target visible].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id locale placement position label target resolves page_kind page_key href visible created_at updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[locale placement position label page_kind page_key href visible].freeze

  COLLECTION_FILTERS = {
    header: ->(resources) { resources.where(placement: 'header') },
    hidden: ->(resources) { resources.where(visible: false) }
  }.freeze

  def display_resource(link)
    "#{link.placement} · #{link.label}"
  end
end
