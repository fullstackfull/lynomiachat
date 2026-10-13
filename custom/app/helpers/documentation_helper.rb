# frozen_string_literal: true

# Lynomia global documentation (docs/global-documentation/11-search-and-locales.md,
# docs/product-refinement/03-documentation-seo.md): the view-level pieces the documentation portal needs beyond
# what the shared portal helpers already give it.
#
# EVERY ADDRESS HERE IS BUILT THE SAME WAY -- the portal's own custom domain if it has one, else the
# installation's help-centre root -- so the canonical, the locale alternates, the Open Graph URL, the
# structured data and the sitemap can never disagree with each other. That is the whole reason they are in one
# helper rather than one expression per view.
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
  def portal_absolute_url(portal, path)
    host = portal.custom_domain.presence || ChatwootApp.help_center_root.to_s
    host = "https://#{host}" unless host.include?('://')
    "#{host.chomp('/')}#{path}"
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

  # The root article plus its translations, published only, ordered by locale so the rendered order is stable.
  def article_translation_family(article)
    root = article.root_article || article
    ([root] + root.associated_articles.to_a).select { |sibling| sibling.status == 'published' }
                                            .uniq(&:id).sort_by(&:locale)
  end
end
