# The site's standing pages -- the ones whose address is a fixed word rather than a catalogue slug.
#
# Each action resolves its row and declares the page's identity. The CONTENT is the row; the ADDRESS is this
# route table. Keeping those apart is what lets an operator rewrite a page without being able to move it, and
# `/features` is a fixed word here for the same reason (SitePage refuses a standing slug that is not its key).
class Marketing::PagesController < Marketing::BaseController
  PAGES = %i[home features channels solutions integrations support about contact faq].freeze

  PAGES.each do |page|
    define_method(page) do
      @site_page = find_site_page(:standing, page)
      return render_marketing_404 if @site_page.nil?

      @marketing_page = Marketing::Page.new(
        route: page,
        title: @site_page.title,
        description: @site_page.description
      )
      render :show
    end
  end
end
