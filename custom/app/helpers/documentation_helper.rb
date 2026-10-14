# frozen_string_literal: true

# Lynomia global documentation (docs/global-documentation/11-search-and-locales.md,
# docs/product-refinement/03-documentation-seo.md): the view-level pieces the documentation portal needs beyond
# what the shared portal helpers already give it.
#
# EVERY ADDRESS HERE IS BUILT THE SAME WAY -- the portal's own custom domain if it has one, else the
# installation's help-centre root -- so the canonical, the locale alternates, the Open Graph URL, the
# structured data and the sitemap can never disagree with each other. That is the whole reason they are in one
# helper rather than one expression per view.
#
# THAT CLAIM USED TO BE FALSE FOR ROBOTS.TXT, and the discrepancy is worth naming because it is what let a bug
# live in two copies (discovery/098-attack-seo-indexability.md R4). `RobotsController#sitemap_lines` carried its
# own copy of the host arithmetic and therefore its own copy of `portal_absolute_url`'s blank-host bug; it now
# calls this helper. `Public::Api::V1::PortalsController#sitemap` carried a third copy, which the sitemap
# template never read -- see REQUESTED CHANGES in the Agent 4 wave-2 report.
module DocumentationHelper
  # The one address an article should be indexed under, whatever query string or layout variant the reader
  # arrived with. Each locale's article has its own slug, so each is its own canonical rather than one pointing
  # at the other -- which is correct, and is what the hreflang set below is for.
  def portal_canonical_url(portal, article)
    portal_absolute_url(portal, generate_article_link(portal.slug, article.slug, false, false))
  end

  def portal_category_canonical_url(portal, category)
    portal_absolute_url(portal, "/hc/#{portal.slug}/#{category.locale}/categories/#{category.slug}")
  end

  # The portal's public root, which is what `og:site_name` and the breadcrumb's first crumb point at.
  def portal_home_url(portal, locale)
    portal_absolute_url(portal, "/hc/#{portal.slug}/#{locale}")
  end

  # One absolute URL on this portal's public host.
  #
  # WITH NO HOST CONFIGURED THIS RETURNS THE PATH, not a fabricated absolute URL. The previous arithmetic
  # produced `https://hc/hc/<portal>/articles/<slug>` from a blank host -- `"https://".chomp('/')` is
  # `"https:/"`, and concatenating a path beginning with `/` re-forms a `//` that makes `hc` the hostname. A
  # crawler was therefore being handed a canonical, an `og:url`, a JSON-LD `url` and a sitemap `<loc>` on a
  # host that does not exist, and the audit's `start_with?('http')` check passed on it
  # (discovery/098-attack-seo-indexability.md R4). A root-relative canonical resolves against the document, so
  # the page stays correct; the audit's host check now fails loudly instead (lib/tasks/documentation_seo_audit.rake).
  #
  # A blank host means neither HELPCENTER_URL nor FRONTEND_URL is set and the portal has no custom domain, which
  # is a deployment bug rather than a supported state. This does not paper over it -- it stops publishing a
  # wrong hostname while the audit reports it.
  def portal_absolute_url(portal, path)
    host = portal_public_host(portal)
    return path if host.blank?

    "#{host}#{path}"
  end

  # The scheme-and-host half of every address above, with no trailing slash. Blank when this installation has
  # configured none. `RobotsController` reads it too, so there is exactly one copy.
  def portal_public_host(portal)
    host = portal.custom_domain.presence || ChatwootApp.help_center_root.to_s
    return '' if host.blank?

    host = "https://#{host}" unless host.include?('://')
    host.chomp('/')
  end

  # THE `<title>` A CRAWLER AND A SEARCH RESULT ACTUALLY READ, which is not `article.title`.
  #
  # All three article layout variants render `article.title` plus the portal's own page title, and
  # `meta['title']` overrides only `<meta name="title">`, `og:title` and `twitter:title` -- never `<title>`
  # (documentation_layout/articles/_meta_head.html.erb:10, articles/_meta_head.html.erb:2). So the length a
  # result page truncates is the length of THIS string, and measuring `article.title` under-reports it by the
  # length of the suffix: `' | Lynomia Chat Documentation'` is 29 characters of the 60-character budget
  # (custom/app/services/documentation/portal_seeder.rb sets `page_title`).
  #
  # Here so the SEO audit measures exactly what the templates emit rather than re-deriving the concatenation --
  # discovery/098-attack-seo-indexability.md R2 and R3, where the audit reported 4 over-long titles and the
  # corpus had 27.
  def documentation_page_title(portal, article)
    "#{article.title} | #{portal.display_title(article.locale)}"
  end

  # THE TRANSLATION FAMILY of one CATEGORY, as [locale, url] pairs including the category itself.
  #
  # A category's translations are found by SLUG, not by an association: `ContentSeeder#upsert_category` is
  # `portal.categories.find_or_initialize_by(slug: section.slug, locale: section.locale)`
  # (custom/app/services/documentation/content_seeder.rb:384-390), so every locale's row of one manifest section
  # carries the SAME slug and differs only by `locale`. `index_categories_on_slug_and_locale_and_portal_id`
  # (db/schema.rb:665, UNIQUE) makes that pair unique per portal, so the group is exact rather than a guess.
  # `associated_category_id` exists on the table and the seeder never writes it, which is why this does not
  # read it.
  #
  # Only locales the portal actually allows are listed: a stale row for a locale that has been removed from
  # `allowed_locales` is no longer served, and announcing it earns a soft-404.
  def portal_category_locale_alternates(portal, category)
    family = category_translation_family(portal, category)
    return [] if family.length < 2

    family.map { |sibling| [sibling.locale, portal_category_canonical_url(portal, sibling)] }
  end

  def portal_category_default_alternate_url(portal, category)
    family = category_translation_family(portal, category)
    return nil if family.length < 2

    default = family.find { |sibling| sibling.locale == portal.default_locale } || family.first
    portal_category_canonical_url(portal, default)
  end

  # THE TRANSLATION FAMILY of one article, as [locale, url] pairs including the article itself.
  #
  # Read from the association the Help Center already uses for translations and that the content seeder already
  # writes (`associated_article_id`, custom/app/services/documentation/content_seeder.rb): every translation
  # hangs off the default-locale article, so the family is that root plus everything hanging off it. Nothing
  # here guesses a sibling slug from a naming convention -- a guessed hreflang that 404s is worse than none.
  #
  # Only PUBLISHED siblings are listed. Telling a crawler that an Arabic version exists while it is still a
  # draft earns a soft-404 rather than a ranking.
  def portal_locale_alternates(portal, article)
    family = article_translation_family(article)
    return [] if family.length < 2

    family.map { |sibling| [sibling.locale, portal_canonical_url(portal, sibling)] }
  end

  # `x-default` names the version to serve a reader whose language we do not have, which is the portal's own
  # default locale. Emitted only when there is more than one language to choose between, because with one
  # language there is nothing to default to.
  def portal_default_alternate_url(portal, article)
    family = article_translation_family(article)
    return nil if family.length < 2

    default = family.find { |sibling| sibling.locale == portal.default_locale } || family.first
    portal_canonical_url(portal, default)
  end

  # BreadcrumbList, so a search result shows "Documentation › Commerce › Connect WooCommerce" rather than a
  # bare URL. Built from the records the page is already rendering; no extra query.
  def documentation_breadcrumb_schema(portal, article)
    crumbs = [[portal.display_title(article.locale), portal_home_url(portal, article.locale)]]
    # `portal_category`, not `category`: this crumb publishes a category NAME and a URL under THIS portal to
    # search engines. A legacy cross-portal row would put another portal's category name in Lynomia's
    # structured data behind a URL that 404s. See app/models/article.rb.
    if (crumb_category = article.portal_category)
      crumbs << [crumb_category.name, portal_category_canonical_url(portal, crumb_category)]
    end
    crumbs << [article.title, portal_canonical_url(portal, article)]

    {
      '@context' => 'https://schema.org', '@type' => 'BreadcrumbList',
      'itemListElement' => crumbs.each_with_index.map do |(name, url), index|
        { '@type' => 'ListItem', 'position' => index + 1, 'name' => name, 'item' => url }
      end
    }
  end

  # TechArticle rather than Article: this is product documentation, and the more specific type is what tells a
  # search engine the page explains how to do something rather than reporting news.
  #
  # `author` is the PORTAL, never the agent who wrote it. A documentation page is published by Lynomia, and
  # putting a staff member's name into public structured data would publish an employee's identity to the
  # whole internet for no reader's benefit.
  def documentation_article_schema(portal, article)
    {
      '@context' => 'https://schema.org', '@type' => 'TechArticle',
      'headline' => article.title,
      'description' => article.meta['description'].presence || article.description.presence,
      'inLanguage' => html_lang_attribute(article.locale),
      'url' => portal_canonical_url(portal, article),
      'datePublished' => article.created_at&.iso8601,
      'dateModified' => article.updated_at&.iso8601,
      'author' => { '@type' => 'Organization', 'name' => portal.display_title(article.locale) },
      'publisher' => { '@type' => 'Organization', 'name' => portal.display_title(article.locale) }
    }.compact
  end

  # One <script type="application/ld+json">. `to_json` escapes the content, and the result is injected with
  # `json_escape` so a `</script>` inside a title cannot break out of the block.
  def documentation_structured_data(payload)
    tag.script(json_escape(payload.to_json).html_safe, type: 'application/ld+json') # rubocop:disable Rails/OutputSafety
  end

  private

  # One manifest section's rows across the portal's allowed locales, ordered by locale so the rendered order is
  # stable. Built from the collection the caller already loaded when it has one, so the sitemap's per-category
  # alternates cost no extra query.
  def category_translation_family(portal, category)
    allowed = portal.allowed_locale_codes
    portal.categories.select { |row| row.slug == category.slug && allowed.include?(row.locale) }
          .uniq(&:id).sort_by(&:locale)
  end

  # The root article plus its translations, published only, ordered by locale so the rendered order is stable.
  def article_translation_family(article)
    root = article.root_article || article
    ([root] + root.associated_articles.to_a).select { |sibling| sibling.status == 'published' }
                                            .uniq(&:id).sort_by(&:locale)
  end
end
