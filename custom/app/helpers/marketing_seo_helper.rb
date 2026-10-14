# The marketing site's structured data.
#
# A SEPARATE MODULE FROM MarketingHelper on purpose. That one is the single URL-resolution point (D9) and is
# already at its length limit; this one is the single structured-data point, and keeping them apart means the
# next reader looking for "what do we tell Google about ourselves" finds one file.
#
# NO CONFLICT WITH THE DOCUMENTATION'S OWN SCHEMA. Documentation V2 emits BreadcrumbList and TechArticle per
# article and nothing else -- there is no top-level Organization or WebSite node anywhere in this application
# (custom/app/helpers/documentation_helper.rb:134-172), and the two URL spaces do not overlap. So the
# Organization and WebSite nodes here are the installation's only ones rather than a second opinion.
#
# EVERY VALUE IS A VERIFIED FACT, which is the owner's rule and is the reason some obvious properties are
# absent:
#   * no `aggregateRating`, `review` or `award` -- none exists;
#   * no `sameAs` social profiles -- the site publishes none, and guessing a handle publishes a claim;
#   * no `foundingDate`, `numberOfEmployees` or `address` -- not published anywhere this repository can read;
#   * no `offers` or `priceRange` -- there is no published price (doc 02 section 4);
#   * no SearchAction on the WebSite node -- the marketing site HAS no search, and a SearchAction naming a
#     URL template that 404s is the kind of structured data that earns a manual action.
module MarketingSeoHelper
  # The company that publishes the site. `url` is the company's own address rather than this site's: the
  # Organization is Lynomia, and the site it publishes is the WebSite node below.
  def marketing_organization_schema
    {
      '@context' => 'https://schema.org', '@type' => 'Organization',
      'name' => t('marketing.brand.name'),
      'url' => COMPANY_URL,
      'logo' => marketing_absolute_url(LOGO_PATH)
    }
  end

  COMPANY_URL = 'https://lynomia.com'.freeze

  # A real file in public/brand-assets, served on this host.
  LOGO_PATH = '/brand-assets/lynomia-logo.png'.freeze

  def marketing_website_schema
    {
      '@context' => 'https://schema.org', '@type' => 'WebSite',
      'name' => t('marketing.site_name'),
      'url' => marketing_url(:home),
      'inLanguage' => marketing_locale,
      'publisher' => { '@type' => 'Organization', 'name' => t('marketing.brand.name'), 'url' => COMPANY_URL }
    }
  end

  # The same trail the page renders, so the structured data and the visible breadcrumb cannot disagree --
  # which is Google's own requirement as well as the honest arrangement. The last crumb has no `path` because
  # it is the current page, and it is given this page's own URL here, which is what the protocol expects.
  def marketing_breadcrumb_schema(trail, current_url)
    {
      '@context' => 'https://schema.org', '@type' => 'BreadcrumbList',
      'itemListElement' => trail.each_with_index.map do |crumb, index|
        { '@type' => 'ListItem', 'position' => index + 1, 'name' => crumb[:label],
          'item' => crumb[:path] ? marketing_absolute_url(crumb[:path]) : current_url }
      end
    }
  end

  # FAQPage, from the SAME rows /faq renders. Not a copy and not a summary: structured data that does not
  # match the visible page is a violation of Google's rule and a lie to the reader who clicked the result.
  def marketing_faq_schema(entries)
    {
      '@context' => 'https://schema.org', '@type' => 'FAQPage',
      'mainEntity' => entries.map do |entry|
        { '@type' => 'Question', 'name' => entry.question,
          'acceptedAnswer' => { '@type' => 'Answer', 'text' => entry.answer } }
      end
    }
  end

  # One <script type="application/ld+json">, escaped twice over: `to_json` escapes the content and
  # `json_escape` neutralises `<`, `>` and `&`, so a `</script>` an operator typed into a heading cannot break
  # out of the block. The same two steps, for the same reason, as DocumentationHelper#documentation_structured_data.
  def marketing_structured_data(payload)
    tag.script(json_escape(payload.to_json).html_safe, type: 'application/ld+json') # rubocop:disable Rails/OutputSafety
  end
end
