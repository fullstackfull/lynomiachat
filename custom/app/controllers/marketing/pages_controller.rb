# The marketing pages themselves.
#
# Each action is a template today; W4 replaces the content source with operator-edited SitePage rows
# (docs/official-website/04-information-architecture.md D10) without changing these addresses, which is why
# the routes and the page keys are fixed now and the storage is not.
#
# `@page` is the key the layout uses for the title, the canonical, the hreflang pair and the breadcrumb, so
# every page declares its identity in exactly one place.
class Marketing::PagesController < Marketing::BaseController
  PAGES = %i[home features channels support].freeze

  PAGES.each do |page|
    define_method(page) do
      @page = page
      render page
    end
  end
end
