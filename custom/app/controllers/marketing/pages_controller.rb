# The site's standing pages -- the ones whose address is a fixed word rather than a catalogue slug.
#
# Each action's only job is to declare the page's identity. W4 replaces the content source with
# operator-edited SitePage rows (docs/official-website/04-information-architecture.md D10) without changing
# these addresses, which is why the routes and the page keys are fixed now and the storage is not.
class Marketing::PagesController < Marketing::BaseController
  PAGES = %i[home features channels solutions integrations support].freeze

  PAGES.each do |page|
    define_method(page) do
      @marketing_page = Marketing::Page.new(
        route: page,
        title: t("marketing.pages.#{page}.title"),
        description: t("marketing.pages.#{page}.description")
      )
      render page
    end
  end
end
