# URL and metadata helpers for the marketing site.
#
# ONE HOST-RESOLUTION POINT, which is D9 and is the lesson DocumentationHelper already paid for: the same host
# arithmetic lived in three copies and emitted `https://hc/hc/...` into canonicals, og:urls, JSON-LD and
# sitemap entries (custom/app/helpers/documentation_helper.rb:7-16, :36-46). Every absolute marketing URL goes
# through `marketing_absolute_url`, so the canonical, the hreflang set, the Open Graph url and the sitemap
# cannot disagree with each other.
module MarketingHelper
  LOCALES = %w[ar en].freeze
  DEFAULT_LOCALE = 'ar'.freeze

  # The sections the SEEDED header and footer link to. It is no longer read at render time -- the navigation
  # comes from site_nav_links, which an operator owns -- but Marketing::ContentBlueprint reads it to build
  # those rows, so the shipped navigation is still declared in one place and still cannot name a page that
  # does not exist.
  NAV_SECTIONS = %i[features channels solutions integrations pricing].freeze

  # `marketing_locale` itself is a helper_method on Marketing::BaseController: the locale is request state the
  # controller resolved from the URL, and reading a controller instance variable from a helper module is both a
  # RuboCop offence and a way for a view to render a locale nobody set.

  def marketing_other_locale = marketing_locale == 'en' ? 'ar' : 'en'

  # Arabic has no prefix, English is `/en`. `locale: nil` is how the route helpers express the unprefixed tree,
  # so an Arabic URL is built by passing nil rather than by string surgery on a path.
  #
  # `page` is either a Symbol naming a standing page (`:features`) or a Marketing::Page, which additionally
  # carries the dynamic segment of a detail page. Both shapes go through here so there is one place that knows
  # how a locale becomes a path -- the header's language switch, the canonical, the hreflang pair and the
  # navigation all call it.
  def marketing_path(page, locale: marketing_locale)
    route = page.is_a?(Marketing::Page) ? page.route : page
    extra = page.is_a?(Marketing::Page) ? page.url_params : {}

    public_send("marketing_#{route}_path", **extra, locale: locale == 'en' ? 'en' : nil)
  end

  def marketing_url(page, locale: marketing_locale) = marketing_absolute_url(marketing_path(page, locale: locale))

  # Returns a root-relative path when no host is configured, rather than fabricating one. The alternative --
  # interpolating a blank host -- is exactly how `https://hc/hc/...` reached production canonicals.
  def marketing_absolute_url(path)
    host = marketing_host
    return path if host.blank?

    "#{host}#{path}"
  end

  # FRONTEND_URL FIRST, AND THAT IS A CORRECTION. This method read `ChatwootApp.help_center_root` first,
  # which is HELPCENTER_URL -- a variable whose purpose in Chatwoot is to name a SEPARATE host for the Help
  # Center. On any installation that sets it to a different hostname, every marketing canonical, hreflang,
  # og:url and sitemap <loc> pointed at the documentation host instead of the website's own. The marketing
  # site is served on the application's own host, so that is the variable to read.
  #
  # The help-centre value is kept as the second choice rather than dropped: on this installation both are the
  # same host, and an installation that has set only HELPCENTER_URL still gets absolute URLs rather than
  # root-relative ones.
  def marketing_host
    host = ENV.fetch('FRONTEND_URL', nil).presence || ChatwootApp.help_center_root.to_s.presence
    return '' if host.blank?

    host = "https://#{host}" unless host.include?('://')
    host.chomp('/')
  end

  # The hreflang set for the current page.
  #
  # ONLY LOCALES WHOSE SIBLING IS PUBLISHED. This used to emit both locales unconditionally from the hardcoded
  # list, which was harmless while every page was a template and is wrong now that a page is a row: an
  # alternate pointing at a draft or archived sibling tells a crawler to index a 404. The documentation side
  # applies the same rule and suppresses the set entirely below two languages
  # (custom/app/helpers/documentation_helper.rb:116-121).
  #
  # `published_locales` is passed in by the caller, which already has the page row and its sibling loaded, so
  # this does no queries of its own.
  def marketing_locale_alternates(page, published_locales: LOCALES)
    locales = LOCALES & Array(published_locales).map(&:to_s)
    return {} if locales.size < 2

    locales.index_with { |locale| marketing_url(page, locale: locale) }
  end

  # The route-helper name behind each catalogue scope, so a view asks for "this entry's page" rather than
  # naming a route helper and a locale argument at every call site.
  ENTRY_ROUTES = { features: :feature, channels: :channel, solutions: :solution,
                   integrations: :integration }.freeze

  def marketing_entry_path(scope, entry, locale: marketing_locale)
    marketing_path(Marketing::Page.new(route: ENTRY_ROUTES.fetch(scope), slug: entry.slug), locale: locale)
  end

  # Where an FAQ answer leads: a standing page named by a Symbol, or a catalogue page named by a
  # [scope, entry_id] pair. One resolver, so an FAQ cannot point at a page that is not in the catalogue --
  # `fetch` on the scope and a raise on a missing entry are deliberate, because a silent nil here would render
  # an answer with no way to read more.
  #
  # NOT NAMED `marketing_faq_path`, which is the route helper for /faq itself. It was, briefly, and the
  # collision took down every page on the site: `marketing_path(:faq)` in the footer resolves its target with
  # `public_send("marketing_faq_path", locale: ...)`, which dispatched to this method instead of the route,
  # handed it a Hash where it expected a link, and raised from the layout. Hence `_href`: a name the router
  # will never generate.
  def marketing_faq_href(link)
    return marketing_path(link) unless link.is_a?(Array)

    scope, entry_id = link
    entry = Marketing::Catalog.entries(scope).find { |candidate| candidate.id == entry_id }
    raise ArgumentError, "FAQ links to unknown #{scope} entry #{entry_id}" if entry.nil?

    marketing_entry_path(scope, entry)
  end

  # The published address on the page today. It is rendered as a real mailto: -- the old page printed it as
  # plain text inside a <span>, so the only contact detail on the site was not clickable.
  SUPPORT_EMAIL = 'info@lynomia.com'.freeze

  def marketing_support_email_url = "mailto:#{SUPPORT_EMAIL}"

  # The operator's own published legal documents. They are linked, never restated: this application does not
  # author policy text, and the version that used to live inside the marketing page as a JavaScript string was
  # a second, unreviewed copy of documents that already exist. The seed puts them in the footer as
  # site_nav_links rows, so an operator can change a URL without a deploy; this constant is what they start as.
  LEGAL_LINKS = {
    about: 'https://lynomia.com/about_us',
    privacy: 'https://lynomia.com/privacy',
    terms: 'https://lynomia.com/terms',
    data_deletion: 'https://lynomia.com/user-data-deletion'
  }.freeze

  # The <title>: the page's own title, then the site name. The page supplies its title rather than the helper
  # deriving it from an I18n key, because a detail page's title lives beside its catalogue entry and a
  # standing page's lives under `marketing.pages` -- one convention in the helper would exclude the other.
  def marketing_page_title(page = marketing_page)
    [page.title, t('marketing.site_name')].compact_blank.join(' | ')
  end

  # The breadcrumb trail for a detail page: site home, the index it belongs to, then the page itself with no
  # link. Built from the same route names the navigation uses, so a trail cannot point somewhere the nav does
  # not go.
  def marketing_breadcrumb(index_route, current_label)
    [
      { label: t('marketing.nav.home'), path: marketing_path(:home) },
      { label: t("marketing.nav.#{index_route}"), path: marketing_path(index_route) },
      { label: current_label, path: nil }
    ]
  end

  def marketing_dir = marketing_locale == 'ar' ? 'rtl' : 'ltr'

  # An operator-entered link target becomes an href here, and only here.
  #
  # `page:<kind>:<key>` is resolved against the published page in the CURRENT locale, so a visitor reading
  # Arabic is sent to the Arabic page even though the operator typed the target once. A target whose page is
  # not published resolves to nil, and every caller renders nothing rather than a dead link -- which is the
  # rule the old footer broke four times.
  def marketing_target_href(target)
    # REFUSED AT THE SINK AS WELL AS ON SAVE. Marketing::SectionSchema refuses a disallowed target when an
    # operator submits one, and this is the second half of the same rule: a target stored before that check
    # existed, or reached by any path that is not the form, still never becomes an href. Every caller already
    # treats a blank href as "no link" and renders the text without one.
    return nil unless Marketing::LinkTarget.valid?(target)

    reference = Marketing::LinkTarget.page_reference(target)
    return target.to_s if reference.nil?

    page = SitePage.live.find_by(locale: marketing_locale, kind: reference[:kind], key: reference[:key])
    return nil if page.nil?

    # A STANDING PAGE'S ROUTE TAKES NO SLUG. `marketing_features_path` has no dynamic segment, so passing one
    # appends `?slug=features` to a perfectly good URL -- which is not a broken link, just a worse one, and
    # the kind of thing a crawler treats as a second address for the same page.
    marketing_path(Marketing::Page.new(route: page_route_for(page),
                                       slug: page.kind == 'standing' ? nil : page.slug))
  end

  def marketing_target_external?(target)
    Marketing::LinkTarget.external?(target)
  end

  # The navigation and footer, from the operator's rows. A link whose target does not resolve is dropped, so
  # an unpublished page cannot put a dead entry in the header.
  def marketing_nav(placement)
    SiteNavLink.placed(marketing_locale, placement).filter_map do |link|
      href = marketing_target_href(link.target)
      next if href.blank?

      { label: link.label, href: href, external: marketing_target_external?(link.target) }
    end
  end

  # The social-card image: the first `image` section's attachment on this page, as an absolute URL.
  #
  # ABSOLUTE AND APP-OWNED. `og:image` is fetched by a crawler with no referer and no session, so it has to
  # be absolute; and it is served from the marketing media route rather than `/rails/active_storage/...`
  # because robots.txt disallows `/rails/` (app/controllers/robots_controller.rb:52) and an ActiveStorage
  # signed id never expires.
  # THE OPERATOR'S CHOICE FIRST. `meta['og_image_id']` is the SEO field on the page, set on the Super Admin
  # editor's SEO panel; with nothing set it falls back to the first `image` section, which is what every
  # seeded page has and what an operator who has not thought about social cards would expect.
  def marketing_og_image_url(page)
    return nil if page.nil?

    chosen = page.meta['og_image_id'].presence ||
             Array(page.sections).find { |candidate| candidate['type'] == 'image' }&.fetch('attachment_id', nil)
    attachment = page.image_for(chosen)
    return nil if attachment.nil?

    marketing_absolute_url(marketing_media_path(id: attachment.id))
  end

  # The figures a `stats` section may read. Each is computed from the verified catalogue rather than stored,
  # so none of them can go stale in an editor. An unknown metric returns nil and the figure is not rendered.
  def marketing_metric(metric)
    case metric.to_s
    when 'channel_count' then Marketing::Catalog.channel_count
    when 'feature_count' then Marketing::Catalog.features.size
    when 'locale_count' then t('marketing.home.stat_locales_value')
    end
  end

  private

  # A standing page's route helper is named after its key (`marketing_features_path`); a detail page's is
  # named after its kind, which is already singular (`marketing_feature_path`).
  def page_route_for(page)
    page.kind == 'standing' ? page.key.to_sym : page.kind.to_sym
  end
end
