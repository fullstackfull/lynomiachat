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

  # The pages the header and footer can link to, in one place, so a nav link cannot point at a route that does
  # not exist. Each entry is a path-helper name; the label comes from the locale file.
  NAV_SECTIONS = %i[features channels solutions integrations pricing].freeze

  # `marketing_locale` itself is a helper_method on Marketing::BaseController: the locale is request state the
  # controller resolved from the URL, and reading a controller instance variable from a helper module is both a
  # RuboCop offence and a way for a view to render a locale nobody set.

  def marketing_locale?(locale)
    marketing_locale == locale
  end

  def marketing_other_locale
    marketing_locale == 'en' ? 'ar' : 'en'
  end

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

  def marketing_url(page, locale: marketing_locale)
    marketing_absolute_url(marketing_path(page, locale: locale))
  end

  # Returns a root-relative path when no host is configured, rather than fabricating one. The alternative --
  # interpolating a blank host -- is exactly how `https://hc/hc/...` reached production canonicals.
  def marketing_absolute_url(path)
    host = marketing_host
    return path if host.blank?

    "#{host}#{path}"
  end

  def marketing_host
    host = ChatwootApp.help_center_root.to_s.presence || ENV.fetch('FRONTEND_URL', '').to_s
    return '' if host.blank?

    host = "https://#{host}" unless host.include?('://')
    host.chomp('/')
  end

  # The hreflang set for the current page: both locales plus x-default pointing at Arabic, which is the
  # primary market. Built from the same helper the canonical uses, so the two cannot drift.
  def marketing_locale_alternates(page)
    LOCALES.index_with { |locale| marketing_url(page, locale: locale) }
  end

  # The route-helper name behind each catalogue scope, so a view asks for "this entry's page" rather than
  # naming a route helper and a locale argument at every call site.
  ENTRY_ROUTES = { features: :feature, channels: :channel }.freeze

  def marketing_entry_path(scope, entry, locale: marketing_locale)
    marketing_path(Marketing::Page.new(route: ENTRY_ROUTES.fetch(scope), slug: entry.slug), locale: locale)
  end

  # The navigation, built only from sections whose route actually exists.
  #
  # This is the rule that makes a dead nav link unrepresentable: the previous site advertised four legal pages
  # and a live chat that led nowhere, and a competitor reviewed in doc 03 ships five menu items pointing at
  # `href="#"`. A section appears here when its page ships, and not before.
  def marketing_nav_items
    NAV_SECTIONS.filter_map do |section|
      next unless respond_to?("marketing_#{section}_path")

      { path: marketing_path(section), label: t("marketing.nav.#{section}") }
    end
  end

  # The published address on the page today. It is rendered as a real mailto: -- the old page printed it as
  # plain text inside a <span>, so the only contact detail on the site was not clickable.
  SUPPORT_EMAIL = 'info@lynomia.com'.freeze

  def marketing_support_email_url = "mailto:#{SUPPORT_EMAIL}"

  # The operator's own published legal documents. They are linked, never restated: this application does not
  # author policy text, and the version that used to live inside the marketing page as a JavaScript string was
  # a second, unreviewed copy of documents that already exist. W4 moves these into operator-managed settings;
  # until then they are declared once, here.
  LEGAL_LINKS = {
    about: 'https://lynomia.com/about_us',
    privacy: 'https://lynomia.com/privacy',
    terms: 'https://lynomia.com/terms',
    data_deletion: 'https://lynomia.com/user-data-deletion'
  }.freeze

  def marketing_legal_links
    LEGAL_LINKS.map { |key, href| { href: href, label: t("marketing.footer.#{key}") } }
  end

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

  def marketing_dir
    marketing_locale == 'ar' ? 'rtl' : 'ltr'
  end
end
