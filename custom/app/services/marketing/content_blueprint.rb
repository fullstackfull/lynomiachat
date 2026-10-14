# What the repository says the official website ships with.
#
# ONE PLACE THAT TURNS THE LOCALE FILES INTO ROWS. `Marketing::ContentSeeder` writes these rows once per
# installation and the operator owns them from then on; this file is the only thing that knows how
# `config/locales/marketing.*.yml` maps onto `site_pages`, `site_nav_links` and `site_faq_entries`.
#
# WHY THE LOCALE FILES ARE STILL THE SOURCE OF THE SEED. They are reviewable, diffable and already the thing
# every claim on the site was checked against (every string traces to
# docs/official-website/02-verified-feature-inventory.md). A second copy of the content in a seed-only YAML
# would be two places to keep honest. After the seed they keep exactly one job: the UI chrome -- button
# labels, state badges, breadcrumb words -- which is interface, not content, and does not belong to an
# operator.
#
# THE DYNAMIC BLOCKS STAY DYNAMIC. A `catalogue` section carries only its copy; the cards inside it are built
# at render time from Marketing::Catalog, so a feature's availability state and its prerequisite cannot be
# edited away. That is the line this whole programme exists to hold.
module Marketing::ContentBlueprint
  # Registration and sign-in are application paths, not content. Named here so the seed and the templates
  # cannot disagree about them.
  REGISTER_PATH = '/app/register'.freeze
  LOGIN_PATH = '/app/login'.freeze
  DOCS_PATH = '/docs'.freeze
  CHANGELOG_PATH = '/changelog'.freeze

  class << self
    # Every page the site ships, for one locale, in the order they should appear in Super Admin.
    def pages(locale)
      I18n.with_locale(locale) { standing_pages + detail_pages }
    end

    def nav_links(locale)
      I18n.with_locale(locale) { header_links + footer_links }
    end

    def faq_entries(locale)
      I18n.with_locale(locale) do
        Marketing::Faq.entries.each_with_index.map do |entry, index|
          kind, key = faq_target(entry.link)
          {
            question: t("marketing.faq.#{entry.id}.question"),
            answer: t("marketing.faq.#{entry.id}.answer"),
            link_label: t("marketing.faq.#{entry.id}.link_label"),
            link_page_kind: kind,
            link_page_key: key,
            position: index
          }
        end
      end
    end

    private

    def t(key, **) = I18n.t(key, **)

    # --- standing pages ---------------------------------------------------------------------------------

    def standing_pages
      [home_page, index_page(:features, :features), index_page(:channels, :channels),
       index_page(:solutions, :solutions), integrations_page, pricing_page, support_page,
       about_page, contact_page, faq_page].each_with_index.map { |page, index| page.merge(position: index) }
    end

    def standing(key, sections)
      {
        kind: 'standing', key: key.to_s, slug: key.to_s.tr('_', '-'),
        title: t("marketing.pages.#{key}.title"),
        description: t("marketing.pages.#{key}.description"),
        heading: t("marketing.pages.#{key}.heading", default: t("marketing.pages.#{key}.title")),
        lede: t("marketing.pages.#{key}.lede", default: nil),
        sections: sections
      }
    end

    def home_page
      standing(:home, [home_hero, home_stats, home_channels, home_features, home_help])
        .merge(heading: t('marketing.home.headline'), lede: t('marketing.home.lede'))
    end

    def home_hero
      { 'type' => 'hero',
        'kicker' => t('marketing.home.kicker'),
        'primary_label' => t('marketing.cta.primary'),
        'primary_target' => REGISTER_PATH,
        'secondary_label' => t('marketing.home.secondary_cta'),
        'secondary_target' => 'page:standing:channels' }
    end

    # The channel count is a `metric`, read from the catalogue at render time rather than typed in: that is
    # what keeps "nine channels" correct on the day a tenth is connected.
    def home_stats
      { 'type' => 'stats',
        'items' => [
          { 'metric' => 'channel_count', 'label' => t('marketing.home.stat_channels') },
          { 'value' => t('marketing.home.stat_locales_value'), 'label' => t('marketing.home.stat_locales') },
          { 'value' => 'API', 'label' => t('marketing.home.stat_api') }
        ] }
    end

    def home_channels
      { 'type' => 'catalogue', 'source' => 'channels',
        'heading' => t('marketing.home.channels_title'),
        'lede' => t('marketing.home.channels_lede'),
        'link_label' => t('marketing.home.channels_link') }
    end

    def home_features
      { 'type' => 'catalogue', 'source' => 'features', 'limit' => '9',
        'heading' => t('marketing.home.features_title'),
        'lede' => t('marketing.home.features_lede'),
        'link_label' => t('marketing.home.features_link') }
    end

    def home_help
      { 'type' => 'cards', 'columns' => '2',
        'heading' => t('marketing.home.help_title'),
        'lede' => t('marketing.home.help_lede'),
        'items' => [
          { 'title' => t('marketing.home.help_docs'),
            'link_label' => t('marketing.home.help_docs'), 'link_target' => DOCS_PATH },
          { 'title' => t('marketing.home.help_support'),
            'link_label' => t('marketing.home.help_support'), 'link_target' => 'page:standing:support' }
        ] }
    end

    # An index page is its copy plus one catalogue block. The cards come from Marketing::Catalog at render
    # time, so nothing about a feature's state is stored here.
    def index_page(key, source)
      standing(key, [{ 'type' => 'catalogue', 'source' => source.to_s }])
    end

    # The integrations index's "this is described elsewhere" paragraph becomes two linked cards rather than a
    # sentence with two inline links. Plain-text bodies cannot carry an inline link (Marketing::SectionSchema
    # explains why), and two cards are the better answer anyway: each destination gets its own label.
    def integrations_page
      standing(:integrations, [
                 { 'type' => 'cards', 'columns' => '2',
                   'items' => [
                     { 'title' => t('marketing.nav.channels'),
                       'body' => t('marketing.pages.integrations.elsewhere_channels'),
                       'link_label' => t('marketing.nav.channels'), 'link_target' => 'page:standing:channels' },
                     { 'title' => t('marketing.features.api_webhooks.name'),
                       'body' => t('marketing.pages.integrations.elsewhere_api'),
                       'link_label' => t('marketing.features.api_webhooks.name'),
                       'link_target' => 'page:feature:api_webhooks' }
                   ] },
                 { 'type' => 'catalogue', 'source' => 'integrations' }
               ])
    end

    def pricing_page
      dimensions = %w[channels agents inboxes stores modules billing].map do |dimension|
        { 'title' => t("marketing.pricing.dimensions.#{dimension}.title"),
          'body' => t("marketing.pricing.dimensions.#{dimension}.body") }
      end

      standing(:pricing, [
                 { 'type' => 'cards', 'columns' => '2',
                   'heading' => t('marketing.pricing.dimensions_title'),
                   'lede' => t('marketing.pricing.dimensions_lede'),
                   'items' => dimensions },
                 { 'type' => 'note', 'body' => t('marketing.pricing.note') }
               ])
    end

    def support_page
      standing(:support, [
                 { 'type' => 'cards', 'columns' => '2',
                   'items' => [
                     { 'title' => t('marketing.support.docs_title'), 'body' => t('marketing.support.docs_body'),
                       'link_label' => t('marketing.support.docs_cta'), 'link_target' => DOCS_PATH },
                     { 'title' => t('marketing.support.ticket_title'), 'body' => t('marketing.support.ticket_body'),
                       'link_label' => t('marketing.support.ticket_cta'), 'link_target' => LOGIN_PATH },
                     { 'title' => t('marketing.support.email_title'), 'body' => t('marketing.support.email_body'),
                       'link_label' => MarketingHelper::SUPPORT_EMAIL,
                       'link_target' => "mailto:#{MarketingHelper::SUPPORT_EMAIL}" },
                     { 'title' => t('marketing.support.changelog_title'), 'body' => t('marketing.support.changelog_body'),
                       'link_label' => t('marketing.support.changelog_cta'), 'link_target' => CHANGELOG_PATH }
                   ] }
               ])
    end

    def about_page
      prose = %w[product honesty arabic company].map do |section|
        { 'type' => 'prose', 'heading' => t("marketing.about.#{section}.title"),
          'body' => t("marketing.about.#{section}.body") }
      end

      standing(:about, prose + [
        { 'type' => 'cards', 'columns' => '2',
          'items' => [
            { 'title' => t('marketing.about.see_features'),
              'link_label' => t('marketing.about.see_features'), 'link_target' => 'page:standing:features' },
            { 'title' => t('marketing.about.company_site'),
              'link_label' => t('marketing.about.company_site'),
              'link_target' => MarketingHelper::LEGAL_LINKS[:about] }
          ] }
      ])
    end

    def contact_page
      standing(:contact, [
                 { 'type' => 'cards', 'columns' => '2',
                   'items' => [
                     { 'title' => t('marketing.contact.email_title'), 'body' => t('marketing.contact.email_body'),
                       'link_label' => MarketingHelper::SUPPORT_EMAIL,
                       'link_target' => "mailto:#{MarketingHelper::SUPPORT_EMAIL}" },
                     { 'title' => t('marketing.contact.quote_title'), 'body' => t('marketing.contact.quote_body'),
                       'link_label' => t('marketing.contact.quote_cta'), 'link_target' => 'page:standing:pricing' },
                     { 'title' => t('marketing.contact.customer_title'), 'body' => t('marketing.contact.customer_body'),
                       'link_label' => t('marketing.footer.sign_in_ticket'), 'link_target' => LOGIN_PATH },
                     { 'title' => t('marketing.contact.docs_title'), 'body' => t('marketing.contact.docs_body'),
                       'link_label' => t('marketing.read_docs'), 'link_target' => DOCS_PATH }
                   ] },
                 { 'type' => 'note', 'body' => t('marketing.contact.no_phone') }
               ])
    end

    # The FAQ's content is site_faq_entries, reached through a `faq` section -- the same shape as a
    # `catalogue` block: the operator owns the block's copy and edits the rows where they live.
    def faq_page
      standing(:faq, [{ 'type' => 'faq' }])
    end

    # --- detail pages -----------------------------------------------------------------------------------

    def detail_pages
      Marketing::Catalog::COLLECTIONS.flat_map do |collection, entries|
        kind = collection.to_s.singularize
        entries.select(&:detail?).each_with_index.map do |entry, index|
          detail_page(kind, collection, entry, index)
        end
      end
    end

    def detail_page(kind, collection, entry, index)
      base = "marketing.#{collection}.#{entry.id}"
      points = Array(I18n.t("#{base}.detail.points", default: [])).map do |point|
        { 'title' => point[:title], 'body' => point[:body] }
      end
      note = t("#{base}.detail.note", default: nil)

      sections = [{ 'type' => 'cards', 'columns' => '2',
                    'heading' => t("#{base}.detail.points_title", default: nil),
                    'items' => points }]
      sections << { 'type' => 'note', 'body' => note } if note.present?

      {
        kind: kind, key: entry.id.to_s, slug: entry.slug,
        title: t("#{base}.name"), description: t("#{base}.summary"),
        heading: t("#{base}.name"), lede: t("#{base}.detail.lede"),
        sections: sections, position: index
      }
    end

    # --- navigation -------------------------------------------------------------------------------------

    def header_links
      MarketingHelper::NAV_SECTIONS.each_with_index.map do |section, index|
        { placement: 'header', label: t("marketing.nav.#{section}"),
          page_kind: 'standing', page_key: section.to_s, position: index }
      end
    end

    def footer_links
      footer_product + footer_resources + footer_support + footer_company
    end

    def footer_product
      MarketingHelper::NAV_SECTIONS.each_with_index.map do |section, index|
        { placement: 'footer_product', label: t("marketing.nav.#{section}"),
          page_kind: 'standing', page_key: section.to_s, position: index }
      end
    end

    def footer_resources
      [{ placement: 'footer_resources', label: t('marketing.footer.docs'), href: DOCS_PATH, position: 0 },
       { placement: 'footer_resources', label: t('marketing.footer.changelog'), href: CHANGELOG_PATH, position: 1 }]
    end

    def footer_support
      [{ placement: 'footer_support', label: t('marketing.footer.support_page'),
         page_kind: 'standing', page_key: 'support', position: 0 },
       { placement: 'footer_support', label: t('marketing.footer.email_us'),
         href: "mailto:#{MarketingHelper::SUPPORT_EMAIL}", position: 1 },
       { placement: 'footer_support', label: t('marketing.footer.sign_in_ticket'), href: LOGIN_PATH, position: 2 }]
    end

    def footer_company
      internal = [%w[about_product about], %w[contact contact], %w[faq faq]].each_with_index.map do |(label, key), index|
        { placement: 'footer_company', label: t("marketing.footer.#{label}"),
          page_kind: 'standing', page_key: key, position: index }
      end

      legal = MarketingHelper::LEGAL_LINKS.each_with_index.map do |(key, href), index|
        { placement: 'footer_company', label: t("marketing.footer.#{key}"), href: href, position: index + 3 }
      end

      internal + legal
    end

    # A FAQ entry's link is a Symbol naming a standing page or a [scope, id] pair naming a catalogue page.
    def faq_target(link)
      return ['standing', link.to_s] unless link.is_a?(Array)

      [link.first.to_s.singularize, link.last.to_s]
    end
  end
end
