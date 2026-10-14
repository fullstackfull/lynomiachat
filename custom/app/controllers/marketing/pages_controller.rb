# The site's standing pages -- the ones whose address is a fixed word rather than a catalogue slug.
#
# Each action resolves its row and declares the page's identity. The CONTENT is the row; the ADDRESS is this
# route table. Keeping those apart is what lets an operator rewrite a page without being able to move it, and
# `/features` is a fixed word here for the same reason (SitePage refuses a standing slug that is not its key).
class Marketing::PagesController < Marketing::BaseController
  PAGES = %i[home features channels solutions integrations support about contact faq].freeze

  # THE HOMEPAGE INHERITED ONE OBLIGATION WHEN IT TOOK `/`.
  #
  # An installation that has not finished setup pushes every visitor to the wizard, and `/` was where that
  # happened (DashboardController#ensure_installation_onboarding, app/controllers/dashboard_controller.rb:39,
  # :60-62). After the cutover `/` is this action on the platform's own host, so the redirect has to live here
  # too or a half-installed deployment would advertise a product it cannot yet run, from a page with no route
  # to the wizard.
  #
  # ON `home` ALONE, because that is the only address that behaviour was ever attached to -- `/features` did
  # not redirect before the cutover and does not now. It covers `/en` as well: both locales are this action.
  # rubocop:disable Rails/LexicallyScopedActionFilter -- `home` is one of the actions PAGES defines below
  before_action :redirect_to_installation_onboarding, only: :home
  # rubocop:enable Rails/LexicallyScopedActionFilter

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

  private

  # The same Redis latch the dashboard reads, read the same way. `Redis::Alfred.get` returns nil when it is
  # not set, which is every normal installation, so the finished product pays one Redis read for the homepage.
  def redirect_to_installation_onboarding
    redirect_to '/installation/onboarding' if ::Redis::Alfred.get(::Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
  end
end
