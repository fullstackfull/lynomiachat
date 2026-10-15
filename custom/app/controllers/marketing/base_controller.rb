# The base for every public marketing page.
#
# It inherits PublicController for the same reason the Help Center does: ActionController::Base with no
# session requirement, no Pundit, and the shared request-exception handling
# (app/controllers/public_controller.rb:3-5). It does NOT inherit Public::Api::V1::Portals::BaseController,
# which is portal-specific -- every one of its filters wants an @portal.
class Marketing::BaseController < PublicController
  layout 'marketing'

  before_action :reject_tenant_custom_domain
  around_action :set_marketing_locale

  helper_method :marketing_locale, :marketing_page, :marketing_published_locales

  # The locale the request resolved to, exposed to the views. It lives here rather than in MarketingHelper
  # because it is request state, and a helper that reads controller instance variables can silently render a
  # locale nobody set.
  def marketing_locale
    @marketing_locale.presence || MarketingHelper::DEFAULT_LOCALE
  end

  # The page's identity, which every discovery tag is built from. Request state, so it lives here for the same
  # reason the locale does. An action that renders without setting it is a bug, and `fetch`-like loudness is
  # what surfaces it: the head partial would otherwise emit a blank title and a canonical pointing at `/`.
  def marketing_page
    @marketing_page || raise("#{self.class.name}##{action_name} rendered without a Marketing::Page")
  end

  # The locales whose version of this page a crawler may be sent to.
  #
  # Read once per request from the row and its sibling, so the head partial's hreflang set costs one extra
  # query rather than one per alternate. A page with no row -- there is none in practice -- falls back to
  # both locales, which is the behaviour the site had before the CMS.
  def marketing_published_locales
    return MarketingHelper::LOCALES if @site_page.nil?

    @marketing_published_locales ||=
      [@site_page, @site_page.translation].compact.select(&:status_published?).map(&:locale)
  end

  # The published row behind this URL, or a 404.
  #
  # THE CONTROLLERS READ `site_pages` AND NOTHING ELSE, which is what "the CMS controls the rendered website"
  # has to mean: there is no locale-file fallback, so the editor and the visitor cannot see different things.
  # The cost is that a missing row is a 404, and the mitigation is not a fallback -- it is `rake
  # marketing:verify`, which the deploy runs and which fails loudly naming every page with no published row.
  #
  # The log line exists for the one case the verify step cannot catch: a row an operator unpublished after
  # the deploy. An operator reading the log sees the kind, the key and the locale rather than a bare 404.
  def find_site_page(kind, key)
    page = page_scope.find_by(locale: marketing_locale, kind: kind.to_s, key: key.to_s)
    return page if page

    Rails.logger.error(
      "[Marketing] no published site_page for #{marketing_locale} #{kind}/#{key} -- " \
      'run `rake marketing:content` to seed it, or publish it in Super Admin'
    )
    nil
  end

  # THE DRAFT PREVIEW, and the whole of it.
  #
  # An operator editing a page needs to see the real page, in the real layout, with the real navigation,
  # before it is published -- a second renderer in Super Admin would show something the published page does
  # not, which is the class of defect this repository has already paid for in the documentation editor. So
  # the preview is the public action with the published-only scope lifted, for a signed-in super admin only.
  #
  # `super_admin_signed_in?` is evaluated ONLY when the parameter is present, so an ordinary public request
  # never touches the Warden session for that scope. A previewed page is not indexable either way: the head
  # partial emits `noindex` for any row that is not published, and the sitemap is built from
  # `SitePage.live`, so a preview URL that leaks is not a draft in search results.
  def preview?
    params[:preview].present? && super_admin_signed_in?
  end

  # The published scope, or every row when a super admin is previewing. Protected rather than private because
  # Marketing::EntriesController looks a page up by slug and uses it too.
  def page_scope
    preview? ? SitePage.all : SitePage.live
  end

  private

  # The same 404 body the rest of the public site serves, and the reason a detail page needs one: a slug that
  # is not in the catalogue must not render an empty template with the slug echoed into the title, which is
  # how a thin-content page gets indexed for a term the product does not have.
  def render_marketing_404
    render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
  end

  # D3: the marketing site answers on the platform's own host, never on a tenant's.
  #
  # A registered portal custom domain resolves through this same route table -- only `/` is special-cased, by
  # DashboardController#render_hc_if_custom_domain (app/controllers/dashboard_controller.rb:64-75). Without
  # this filter, `/pricing` would also answer on docs.customer.example, putting Lynomia's marketing inside a
  # customer's own Help Center domain.
  #
  # The check is a positive lookup for a portal holding this host, rather than a comparison against
  # FRONTEND_URL. DomainHelper.chatwoot_domain? reads two environment variables
  # (app/controllers/concerns/domain_helper.rb:2-4) that are unset in several environments, so requiring a
  # match there would make the whole site 404 wherever they are blank -- failing in the direction that hides
  # the site rather than the direction that protects a tenant.
  def reject_tenant_custom_domain
    return if request.host.blank?
    return unless Portal.where.not(custom_domain: [nil, '']).exists?(custom_domain: request.host)

    render_marketing_404
  end

  # Arabic is the default and is unprefixed; English is `/en` (D5). The locale is a URL decision made here,
  # server-side -- never a client-side swap, which is the defect that flipped every Arabic visitor to English
  # on the old page (docs/official-website/01-current-state-audit.md section 3.3).
  #
  # AN `around_action` WITH `with_locale`, NOT A BARE ASSIGNMENT. This was `I18n.locale = @marketing_locale`
  # in a `before_action`, which sets the locale and never puts it back. `I18n.locale` is a thread variable
  # (i18n 1.15.2 stores it with `Thread.current.thread_variable_set(:i18n_config, ...)`) and nothing in Rails
  # restores it per request, so a Puma thread that served an Arabic marketing page kept `:ar` afterwards.
  #
  # Measured, on the real host: `I18n.locale = :en; get '/'` leaves `I18n.locale == :ar`.
  #
  # Most of the application was safe from that because it sets its locale explicitly on the way in --
  # `ApplicationController:11`, `Api::V1::Accounts::BaseController:6`, `DashboardController:38` and
  # `Public::Api::V1::Portals::BaseController:7` all use `around_action` + `I18n.with_locale`. The exposed
  # ones are the `PublicController` descendants that set no locale of their own: `CsatSurveyController`,
  # `InboxesController`, `Portals::MediaController` and this controller's own `MediaController`. A CSAT
  # survey rendered on a thread that had just served the Arabic homepage came back in Arabic.
  #
  # `with_locale` restores in an `ensure`, which is the form `app/controllers/concerns/switch_locale.rb:56`
  # already documents in this repository: "Ensure locale won't bleed into other requests".
  def set_marketing_locale(&)
    @marketing_locale = params[:locale] == 'en' ? 'en' : 'ar'
    I18n.with_locale(@marketing_locale, &)
  end
end
